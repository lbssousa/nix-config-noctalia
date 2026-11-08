#include "prompt_bridge.h"

#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <format>
#include <climits>
#include <glob.h>
#include <poll.h>
#include <sys/inotify.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

namespace secret_prompt {

  namespace {

    // Same separator `noctalia msg` puts between the caller's cwd and the command.
    constexpr char kCallerCwdSeparator = '\x1e';
    constexpr auto kAckTimeout = std::chrono::seconds(3);
    constexpr auto kAlivePeriod = std::chrono::seconds(2);
    constexpr std::size_t kReplyMax = 64 * 1024;

    int g_signalPipe[2] = {-1, -1};

    void onSignal(int /*sig*/) {
      const char byte = 1;
      const int saved = errno;
      (void)!::write(g_signalPipe[1], &byte, 1);
      errno = saved;
    }

    std::string runtimeDir() {
      if (const char* dir = std::getenv("XDG_RUNTIME_DIR"); dir != nullptr && dir[0] != '\0') {
        return dir;
      }
      return std::format("/run/user/{}", ::getuid());
    }

    // The shell's IPC socket. Without WAYLAND_DISPLAY (a gpg-agent started before the session
    // exported it), the only Noctalia socket in the runtime dir.
    std::string ipcSocketPath() {
      const std::string runtime = runtimeDir();
      if (const char* display = std::getenv("WAYLAND_DISPLAY"); display != nullptr && display[0] != '\0') {
        return runtime + "/noctalia-" + display + ".sock";
      }
      const std::string pattern = runtime + "/noctalia-*.sock";
      glob_t matches{};
      std::string path;
      if (::glob(pattern.c_str(), 0, nullptr, &matches) == 0 && matches.gl_pathc == 1) {
        path = matches.gl_pathv[0];
      }
      ::globfree(&matches);
      return path;
    }

    int connectIpc() {
      const std::string path = ipcSocketPath();
      sockaddr_un addr{};
      addr.sun_family = AF_UNIX;
      if (path.empty() || path.size() >= sizeof(addr.sun_path)) {
        return -1;
      }
      std::memcpy(addr.sun_path, path.c_str(), path.size() + 1);
      const int fd = ::socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
      if (fd < 0) {
        return -1;
      }
      timeval tv{.tv_sec = 2, .tv_usec = 0};
      ::setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
      ::setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
      if (::connect(fd, reinterpret_cast<const sockaddr*>(&addr), sizeof(addr)) < 0) {
        ::close(fd);
        return -1;
      }
      return fd;
    }

    // One `noctalia msg` round trip. False when the shell is not running or answered "error:".
    bool sendIpc(const std::string& command) {
      const int fd = connectIpc();
      if (fd < 0) {
        return false;
      }
      std::string line = "/";
      line += kCallerCwdSeparator;
      line += command;
      std::size_t sent = 0;
      while (sent < line.size()) {
        const auto n = ::write(fd, line.data() + sent, line.size() - sent);
        if (n < 0) {
          if (errno == EINTR) {
            continue;
          }
          ::close(fd);
          return false;
        }
        sent += static_cast<std::size_t>(n);
      }
      ::shutdown(fd, SHUT_WR);
      std::string response;
      char buf[512];
      while (true) {
        const auto n = ::read(fd, buf, sizeof(buf));
        if (n < 0 && errno == EINTR) {
          continue;
        }
        if (n <= 0) {
          break;
        }
        response.append(buf, static_cast<std::size_t>(n));
      }
      ::close(fd);
      return !response.starts_with("error:");
    }

    bool shellAlive() {
      const int fd = connectIpc();
      if (fd < 0) {
        return false;
      }
      ::close(fd);
      return true;
    }

    std::string randomId() {
      unsigned char bytes[16];
      std::size_t got = 0;
      while (got < sizeof(bytes)) {
        const auto n = ::getrandom(bytes + got, sizeof(bytes) - got, 0);
        if (n < 0) {
          if (errno == EINTR) {
            continue;
          }
          std::abort();
        }
        got += static_cast<std::size_t>(n);
      }
      std::string id;
      for (const unsigned char b : bytes) {
        id += std::format("{:02x}", b);
      }
      return id;
    }

    const char* kindName(PromptKind kind) {
      switch (kind) {
      case PromptKind::Pin:
        return "pin";
      case PromptKind::Confirm:
        return "confirm";
      case PromptKind::Message:
        return "message";
      }
      return "pin";
    }

    // Reads and removes `path`; empty optional-like result when it does not exist yet.
    bool takeFile(const std::string& path, std::string& contents) {
      const int fd = ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
      if (fd < 0) {
        return false;
      }
      contents.clear();
      char buf[4096];
      while (contents.size() < kReplyMax) {
        const auto n = ::read(fd, buf, sizeof(buf));
        if (n < 0 && errno == EINTR) {
          continue;
        }
        if (n <= 0) {
          break;
        }
        contents.append(buf, static_cast<std::size_t>(n));
      }
      ::explicit_bzero(buf, sizeof(buf));
      ::close(fd);
      ::unlink(path.c_str());
      return true;
    }

    class PromptDir {
    public:
      explicit PromptDir(const std::string& id) {
        const std::string base = runtimeDir() + "/noctalia-secret-prompts";
        if (::mkdir(base.c_str(), 0700) < 0 && errno != EEXIST) {
          return;
        }
        struct stat st{};
        if (::lstat(base.c_str(), &st) < 0 || !S_ISDIR(st.st_mode) || st.st_uid != ::getuid()) {
          return;
        }
        ::chmod(base.c_str(), 0700);
        m_path = base + "/" + id;
        if (::mkdir(m_path.c_str(), 0700) < 0) {
          m_path.clear();
        }
      }
      ~PromptDir() {
        if (m_path.empty()) {
          return;
        }
        std::error_code ec;
        for (const auto* name : {"/ack", "/reply"}) {
          std::filesystem::remove(m_path + name, ec);
        }
        ::rmdir(m_path.c_str());
      }
      PromptDir(const PromptDir&) = delete;
      PromptDir& operator=(const PromptDir&) = delete;

      [[nodiscard]] bool ok() const { return !m_path.empty(); }
      [[nodiscard]] const std::string& path() const { return m_path; }

    private:
      std::string m_path;
    };

    void installSignalHandlers() {
      if (g_signalPipe[0] >= 0) {
        return;
      }
      if (::pipe2(g_signalPipe, O_CLOEXEC | O_NONBLOCK) < 0) {
        return;
      }
      struct sigaction sa{};
      sa.sa_handler = onSignal;
      sigemptyset(&sa.sa_mask);
      for (const int sig : {SIGTERM, SIGINT, SIGHUP}) {
        ::sigaction(sig, &sa, nullptr);
      }
    }

  } // namespace

  std::string jsonEscape(std::string_view text) {
    std::string out;
    out.reserve(text.size() + 2);
    for (const char ch : text) {
      const auto byte = static_cast<unsigned char>(ch);
      switch (ch) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (byte < 0x20 || byte == 0x7f) {
          out += std::format("\\u{:04x}", byte);
        } else {
          out.push_back(ch);
        }
      }
    }
    return out;
  }

  std::string requestJson(const PromptRequest& r, std::string_view id) {
    const auto str = [](std::string_view key, std::string_view value) {
      return std::format("\"{}\":\"{}\"", key, jsonEscape(value));
    };
    const auto boolean = [](std::string_view key, bool value) {
      return std::format("\"{}\":{}", key, value ? "true" : "false");
    };
    std::string out = "{";
    out += str("id", id) + ",";
    out += str("origin", r.origin == PromptOrigin::Gpg ? "gpg" : "ssh") + ",";
    out += str("kind", kindName(r.kind)) + ",";
    out += str("title", r.title) + ",";
    out += str("description", r.description) + ",";
    out += str("prompt", r.prompt) + ",";
    out += str("error", r.error) + ",";
    out += str("ok", r.okLabel) + ",";
    out += str("cancel", r.cancelLabel) + ",";
    out += str("notok", r.notOkLabel) + ",";
    out += boolean("repeat", r.wantsRepeat) + ",";
    out += str("repeat_prompt", r.repeatPrompt) + ",";
    out += str("repeat_error", r.repeatError) + ",";
    out += boolean("one_button", r.oneButton) + ",";
    out += boolean("visible", r.visibleInput) + ",";
    out += boolean("no_buttons", r.noButtons);
    out += "}";
    return out;
  }

  bool pluginReachable() { return sendIpc(std::format("plugin {} all ping", kPluginService)); }

  BridgeAnswer askPlugin(const PromptRequest& request, int watchFd) {
    BridgeAnswer answer;
    installSignalHandlers();

    const std::string id = randomId();
    PromptDir dir(id);
    if (!dir.ok()) {
      return answer;
    }

    const int inotifyFd = ::inotify_init1(IN_CLOEXEC | IN_NONBLOCK);
    if (inotifyFd < 0 || ::inotify_add_watch(inotifyFd, dir.path().c_str(), IN_CLOSE_WRITE | IN_MOVED_TO) < 0) {
      if (inotifyFd >= 0) {
        ::close(inotifyFd);
      }
      return answer;
    }

    if (!sendIpc(std::format("plugin {} all request {}", kPluginService, requestJson(request, id)))) {
      ::close(inotifyFd);
      return answer;
    }

    const auto cancelRemote = [&id] { (void)sendIpc(std::format("plugin {} all cancel {}", kPluginService, id)); };

    using Clock = std::chrono::steady_clock;
    const auto start = Clock::now();
    const auto deadline = request.timeoutSeconds > 0 ? start + std::chrono::seconds(request.timeoutSeconds)
                                                     : Clock::time_point::max();
    auto nextAlive = start + kAlivePeriod;
    bool acked = false;
    const std::string ackPath = dir.path() + "/ack";
    const std::string replyPath = dir.path() + "/reply";

    while (true) {
      std::string contents;
      if (!acked && takeFile(ackPath, contents)) {
        acked = true;
      }
      if (takeFile(replyPath, contents)) {
        if (contents.starts_with("ok\n") || contents == "ok") {
          answer.status = BridgeStatus::Ok;
          if (contents.size() > 3) {
            answer.value.assign(contents, 3);
          }
        } else if (contents.starts_with("notok")) {
          answer.status = BridgeStatus::NotOk;
        } else {
          answer.status = BridgeStatus::Cancelled;
        }
        wipe(contents);
        break;
      }

      const auto now = Clock::now();
      if (!acked && now - start > kAckTimeout) {
        cancelRemote();
        answer.status = BridgeStatus::Unreachable;
        break;
      }
      if (now >= deadline) {
        cancelRemote();
        answer.status = BridgeStatus::TimedOut;
        break;
      }
      if (now >= nextAlive) {
        nextAlive = now + kAlivePeriod;
        if (!shellAlive()) {
          answer.status = BridgeStatus::Cancelled;
          break;
        }
      }

      pollfd fds[3] = {
          {.fd = inotifyFd, .events = POLLIN, .revents = 0},
          {.fd = g_signalPipe[0], .events = POLLIN, .revents = 0},
          {.fd = watchFd, .events = 0, .revents = 0}, // POLLHUP/POLLERR are always reported
      };
      const auto until = std::min({deadline, nextAlive, acked ? Clock::time_point::max() : start + kAckTimeout});
      const auto waitMs = std::chrono::duration_cast<std::chrono::milliseconds>(until - now).count();
      const int timeout = static_cast<int>(std::clamp<long long>(waitMs, 0, 1000));
      if (::poll(fds, watchFd >= 0 ? 3 : 2, timeout) < 0 && errno != EINTR) {
        cancelRemote();
        answer.status = BridgeStatus::Aborted;
        break;
      }
      if (fds[1].revents != 0) {
        cancelRemote();
        answer.status = BridgeStatus::Aborted;
        break;
      }
      if (watchFd >= 0 && (fds[2].revents & (POLLHUP | POLLERR | POLLNVAL)) != 0) {
        cancelRemote();
        answer.status = BridgeStatus::Aborted;
        break;
      }
      if (fds[0].revents != 0) {
        char buf[sizeof(inotify_event) + NAME_MAX + 1];
        while (::read(inotifyFd, buf, sizeof(buf)) > 0) {
        }
      }
    }

    ::close(inotifyFd);
    return answer;
  }

} // namespace secret_prompt
