#include "prompt_bridge.h"
#include "test_check.h"

#include <string>

namespace {

  using secret_prompt::PromptKind;
  using secret_prompt::PromptOrigin;
  using secret_prompt::PromptRequest;

  void testEscape() {
    TEST_CHECK(secret_prompt::jsonEscape("plain") == "plain");
    TEST_CHECK(secret_prompt::jsonEscape("a\"b\\c") == "a\\\"b\\\\c");
    TEST_CHECK(secret_prompt::jsonEscape("line\nnext\ttab") == "line\\nnext\\ttab");
    TEST_CHECK(secret_prompt::jsonEscape(std::string("\x01\x1f", 2)) == "\\u0001\\u001f");
    TEST_CHECK(secret_prompt::jsonEscape("ção") == "ção");
  }

  void testRequest() {
    PromptRequest request;
    request.kind = PromptKind::Pin;
    request.origin = PromptOrigin::Gpg;
    request.description = "Please enter\nthe passphrase";
    request.wantsRepeat = true;
    const std::string json = secret_prompt::requestJson(request, "abc");
    // One line: the IPC socket reads the command up to the first newline.
    TEST_CHECK(json.find('\n') == std::string::npos);
    TEST_CHECK(json.starts_with("{\"id\":\"abc\",\"origin\":\"gpg\",\"kind\":\"pin\""));
    TEST_CHECK(json.contains("\"description\":\"Please enter\\nthe passphrase\""));
    TEST_CHECK(json.contains("\"repeat\":true"));
    TEST_CHECK(json.ends_with("\"no_buttons\":false}"));

    request.kind = PromptKind::Confirm;
    request.origin = PromptOrigin::Ssh;
    const std::string confirm = secret_prompt::requestJson(request, "id");
    TEST_CHECK(confirm.contains("\"origin\":\"ssh\",\"kind\":\"confirm\""));
  }

} // namespace

int main() {
  testEscape();
  testRequest();
  return 0;
}
