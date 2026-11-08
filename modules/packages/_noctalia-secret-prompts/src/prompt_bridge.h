#pragma once

#include "assuan_session.h"

#include <string>
#include <string_view>

// Shows a PromptRequest through the lbssousa/secret-prompts Noctalia plugin.
//
// The request goes out over the shell's IPC socket ($XDG_RUNTIME_DIR/noctalia-$WAYLAND_DISPLAY.sock,
// what `noctalia msg plugin` uses) and carries only what the panel shows, never a secret. The
// answer comes back as a file the plugin writes into a private directory this process creates:
//
//   $XDG_RUNTIME_DIR/noctalia-secret-prompts/<id>/   0700, made here
//     ack     written by the plugin as soon as the request is queued
//     reply   "ok\n<value>", "notok" or "cancel"; new files from the plugin are 0600
//
// The directory is removed before returning.
namespace secret_prompt {

  inline constexpr std::string_view kPluginService = "lbssousa/secret-prompts:service";

  enum class BridgeStatus {
    Unreachable, // no shell, or the plugin never acknowledged the request
    Ok,          // GETPIN answered (value set), CONFIRM confirmed, MESSAGE dismissed
    NotOk,       // CONFIRM answered "no"
    Cancelled,   // the user cancelled, or the shell went away mid-prompt
    TimedOut,    // SETTIMEOUT elapsed
    Aborted,     // a signal, or the watched fd hung up (the agent gave up)
  };

  struct BridgeAnswer {
    BridgeStatus status = BridgeStatus::Unreachable;
    std::string value; // wipe() after use
  };

  // True when the shell answers on its IPC socket and the plugin service is loaded.
  [[nodiscard]] bool pluginReachable();

  // Blocks until the prompt is settled. `watchFd` (pinentry: stdin from the gpg-agent) hanging
  // up aborts the prompt; pass -1 for none. SIGTERM, SIGINT and SIGHUP abort it too.
  [[nodiscard]] BridgeAnswer askPlugin(const PromptRequest& request, int watchFd);

  // Exposed for tests.
  [[nodiscard]] std::string requestJson(const PromptRequest& request, std::string_view id);
  [[nodiscard]] std::string jsonEscape(std::string_view text);

} // namespace secret_prompt
