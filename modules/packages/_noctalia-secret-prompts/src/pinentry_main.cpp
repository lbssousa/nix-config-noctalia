// noctalia-pinentry: gpg-agent's pinentry-program. Speaks the pinentry Assuan protocol with the
// agent on stdin/stdout and shows each GETPIN/CONFIRM/MESSAGE in the lbssousa/secret-prompts
// Noctalia plugin. Without a reachable shell or plugin (TTY, SSH session, Noctalia not running)
// it execs $NOCTALIA_PINENTRY_FALLBACK with the same arguments, e.g. pinentry-curses.

#include "assuan_session.h"
#include "prompt_bridge.h"

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>

namespace {

  bool writeAll(int fd, const std::string& data) {
    std::size_t sent = 0;
    while (sent < data.size()) {
      const auto n = ::write(fd, data.data() + sent, data.size() - sent);
      if (n < 0) {
        if (errno == EINTR) {
          continue;
        }
        return false;
      }
      sent += static_cast<std::size_t>(n);
    }
    return true;
  }

  [[noreturn]] void fallback(char** argv) {
    const char* program = std::getenv("NOCTALIA_PINENTRY_FALLBACK");
    if (program != nullptr && program[0] != '\0') {
      argv[0] = const_cast<char*>(program);
      ::execv(program, argv);
      std::fprintf(stderr, "noctalia-pinentry: cannot run %s: %s\n", program, std::strerror(errno));
    } else {
      std::fprintf(stderr, "noctalia-pinentry: Noctalia is not reachable and no fallback is set\n");
    }
    std::_Exit(1);
  }

} // namespace

int main(int /*argc*/, char** argv) {
  using secret_prompt::AssuanSession;
  using secret_prompt::BridgeStatus;

  std::signal(SIGPIPE, SIG_IGN);
  if (!secret_prompt::pluginReachable()) {
    fallback(argv);
  }

  AssuanSession session(secret_prompt::PromptOrigin::Gpg);
  if (!writeAll(STDOUT_FILENO, AssuanSession::greeting())) {
    return 1;
  }

  std::string buffer;
  std::string out;
  char chunk[1024];
  while (true) {
    const auto newline = buffer.find('\n');
    if (newline == std::string::npos) {
      if (buffer.size() > secret_prompt::kAssuanLineMax) {
        return 1;
      }
      const auto n = ::read(STDIN_FILENO, chunk, sizeof(chunk));
      if (n < 0 && errno == EINTR) {
        continue;
      }
      if (n <= 0) {
        return 0;
      }
      buffer.append(chunk, static_cast<std::size_t>(n));
      continue;
    }
    const std::string line = buffer.substr(0, newline);
    buffer.erase(0, newline + 1);

    out.clear();
    const auto action = session.feedLine(line, out);
    if (action == AssuanSession::Action::Prompt) {
      auto answer = secret_prompt::askPlugin(session.request(), STDIN_FILENO);
      switch (answer.status) {
      case BridgeStatus::Ok:
        if (session.request().kind == secret_prompt::PromptKind::Pin) {
          session.answerPin(answer.value, out);
        } else {
          session.answerConfirm(true, out);
        }
        break;
      case BridgeStatus::NotOk:
        session.answerConfirm(false, out);
        break;
      case BridgeStatus::TimedOut:
        session.answerTimeout(out);
        break;
      case BridgeStatus::Aborted:
        secret_prompt::wipe(answer.value);
        return 1;
      case BridgeStatus::Unreachable:
      case BridgeStatus::Cancelled:
        session.answerCancel(out);
        break;
      }
      secret_prompt::wipe(answer.value);
    }
    const bool written = writeAll(STDOUT_FILENO, out);
    secret_prompt::wipe(out);
    if (!written) {
      return 1;
    }
    if (action == AssuanSession::Action::Close) {
      return 0;
    }
  }
}
