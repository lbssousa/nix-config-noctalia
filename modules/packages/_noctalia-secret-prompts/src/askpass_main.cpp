// noctalia-askpass: SSH_ASKPASS for ssh, ssh-add and git. The prompt comes in argv[1] and
// SSH_ASKPASS_PROMPT selects the kind ("confirm", "none" or a secret). The prompt is shown in the
// lbssousa/secret-prompts Noctalia plugin; answers are printed on stdout and cancelling exits
// with status 1. Without a reachable shell it runs $NOCTALIA_ASKPASS_FALLBACK, or fails.

#include "askpass_plan.h"
#include "assuan_session.h"
#include "prompt_bridge.h"

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>

int main(int argc, char** argv) {
  using secret_prompt::AskpassMode;
  using secret_prompt::AssuanSession;
  using secret_prompt::BridgeStatus;

  std::signal(SIGPIPE, SIG_IGN);
  const std::string prompt = argc > 1 ? argv[1] : "";

  if (!secret_prompt::pluginReachable()) {
    if (const char* program = std::getenv("NOCTALIA_ASKPASS_FALLBACK"); program != nullptr && program[0] != '\0') {
      argv[0] = const_cast<char*>(program);
      ::execv(program, argv);
      std::fprintf(stderr, "noctalia-askpass: cannot run %s: %s\n", program, std::strerror(errno));
      return 1;
    }
    std::fprintf(stderr, "noctalia-askpass: Noctalia is not reachable\n");
    return 1;
  }

  // The same Assuan commands a pinentry client would send, run through a local session so the
  // plugin gets one request shape for both clients.
  const secret_prompt::AskpassPlan plan = secret_prompt::planAskpass(prompt, std::getenv("SSH_ASKPASS_PROMPT"));
  AssuanSession session(secret_prompt::PromptOrigin::Ssh);
  std::string out;
  for (const auto& command : plan.commands) {
    if (session.feedLine(command, out) == AssuanSession::Action::Prompt) {
      break;
    }
  }
  if (!session.waiting()) {
    std::fprintf(stderr, "noctalia-askpass: malformed prompt\n");
    return 1;
  }

  auto answer = secret_prompt::askPlugin(session.request(), -1);
  int status = answer.status == BridgeStatus::Ok ? 0 : 1;
  switch (plan.mode) {
  case AskpassMode::Secret:
    if (status == 0) {
      answer.value += '\n';
      std::fwrite(answer.value.data(), 1, answer.value.size(), stdout);
      std::fflush(stdout);
    }
    break;
  case AskpassMode::Confirm:
    break;
  case AskpassMode::Info:
    // ssh kills the notice once the key was used; that is not a failure.
    if (answer.status == BridgeStatus::Aborted) {
      status = 0;
    }
    break;
  }
  secret_prompt::wipe(answer.value);
  return status;
}
