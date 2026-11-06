#include "flutter_window.h"

#include <optional>
#include <string>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"


namespace {
std::wstring ToWide(const std::string& value) {
  if (value.empty()) return L"";
  const int chars = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.c_str(), -1, nullptr, 0);
  if (chars <= 0) return L"";
  std::wstring wide(chars, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.c_str(),
                          -1, wide.data(), chars) == 0) {
    return L"";
  }
  wide.resize(chars - 1);
  return wide;
}
std::string Argument(const flutter::EncodableValue* args, const char* name) {
  if (!args) return "";
  const auto* map = std::get_if<flutter::EncodableMap>(args);
  if (!map) return "";
  const auto item = map->find(flutter::EncodableValue(std::string(name)));
  if (item == map->end()) return "";
  const auto* val = std::get_if<std::string>(&item->second);
  return val ? *val : "";
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  storage_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "butlerly/storage_capacity",
          &flutter::StandardMethodCodec::GetInstance());
  storage_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto method = call.method_name();
        if (method == "publishNoReplace") {
          const auto source = ToWide(Argument(call.arguments(), "source"));
          const auto dest = ToWide(Argument(call.arguments(), "destination"));
          if (source.empty() || dest.empty()) {
            result->Error("invalid_path", "Both paths are required.");
          } else if (CreateHardLinkW(dest.c_str(), source.c_str(), nullptr)) {
            result->Success();
          } else {
            result->Error("publish_failed", "Atomic no-replace hard link failed.");
          }
          return;
        }
        if (method == "availableBytes" || method == "filesystemId") {
          const auto value = ToWide(Argument(call.arguments(), "path"));
          if (value.empty()) {
            result->Error("invalid_path", "Storage path required.");
            return;
          }
          if (method == "availableBytes") {
            ULARGE_INTEGER freeBytes;
            if (!GetDiskFreeSpaceExW(value.c_str(), &freeBytes, nullptr, nullptr)) {
              result->Error("storage_unavailable", "Free space unavailable.");
              return;
            }
            result->Success(flutter::EncodableValue(
                static_cast<int64_t>(freeBytes.QuadPart)));
            return;
          }
          wchar_t mount[MAX_PATH] = {};
          DWORD serial = 0;
          if (!GetVolumePathNameW(value.c_str(), mount, MAX_PATH) ||
              !GetVolumeInformationW(mount, nullptr, 0, &serial,
                                      nullptr, nullptr, nullptr, 0)) {
            result->Error("storage_unavailable", "Volume identity unavailable.");
            return;
          }
          // Mounted volume path and serial prevent accidental identity matches
          // between different Windows drives with coincidentally equal serials.
          const std::wstring mountName(mount);
          std::string resultId = std::to_string(serial);
          resultId += ":";
          for (const auto ch : mountName) {
            resultId += (ch <= 127 ? static_cast<char>(ch) : '?');
          }
          result->Success(flutter::EncodableValue(resultId));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  storage_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
