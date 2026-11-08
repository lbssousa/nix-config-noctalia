#include "askpass_plan.h"

#include "assuan_session.h"

#include <algorithm>
#include <cctype>

namespace secret_prompt {

  namespace {

    std::string lowercase(std::string_view text) {
      std::string out(text);
      std::ranges::transform(out, out.begin(), [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
      return out;
    }

  } // namespace

  bool askpassWantsVisibleInput(std::string_view prompt) {
    const std::string lower = lowercase(prompt);
    return lower.starts_with("username") || lower.contains("user name") || lower.contains("(yes/no");
  }

  AskpassPlan planAskpass(std::string_view prompt, const char* promptEnv) {
    AskpassPlan plan;
    const std::string_view mode = promptEnv != nullptr ? promptEnv : "";
    if (mode == "confirm") {
      plan.mode = AskpassMode::Confirm;
    } else if (mode == "none") {
      plan.mode = AskpassMode::Info;
    }

    if (plan.mode == AskpassMode::Secret && askpassWantsVisibleInput(prompt)) {
      plan.commands.emplace_back("OPTION noctalia-visible-input");
    }
    if (plan.mode == AskpassMode::Info) {
      plan.commands.emplace_back("OPTION noctalia-no-buttons");
    }
    // ssh prompts end with ": " or a newline; the panel has its own spacing.
    std::string_view text = prompt;
    while (!text.empty() && (text.back() == ' ' || text.back() == '\n')) {
      text.remove_suffix(1);
    }
    plan.commands.push_back("SETDESC " + percentEncode(text));
    switch (plan.mode) {
    case AskpassMode::Secret:
      plan.commands.emplace_back("GETPIN");
      break;
    case AskpassMode::Confirm:
      plan.commands.emplace_back("CONFIRM");
      break;
    case AskpassMode::Info:
      plan.commands.emplace_back("MESSAGE");
      break;
    }
    return plan;
  }

} // namespace secret_prompt
