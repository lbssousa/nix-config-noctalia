#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace secret_prompt {

  enum class AskpassMode {
    Secret,  // answer goes to stdout
    Confirm, // SSH_ASKPASS_PROMPT=confirm: exit status only
    Info,    // SSH_ASKPASS_PROMPT=none: shown until ssh kills us
  };

  struct AskpassPlan {
    AskpassMode mode = AskpassMode::Secret;
    // Assuan commands for a local session, the last one being GETPIN, CONFIRM or MESSAGE.
    std::vector<std::string> commands;
  };

  // `promptEnv` is SSH_ASKPASS_PROMPT (may be null).
  [[nodiscard]] AskpassPlan planAskpass(std::string_view prompt, const char* promptEnv);
  // Prompts that ask for a name or a yes/no answer rather than a secret.
  [[nodiscard]] bool askpassWantsVisibleInput(std::string_view prompt);

} // namespace secret_prompt
