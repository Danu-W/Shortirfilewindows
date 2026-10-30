#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

void RegisterUriScheme() {
  wchar_t exe_path[MAX_PATH];
  if (!::GetModuleFileNameW(nullptr, exe_path, MAX_PATH)) {
    return;
  }

  const std::wstring command = L"\"" + std::wstring(exe_path) + L"\" \"%1\"";

  HKEY scheme_key;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\shortirfile", 0,
                        nullptr, 0, KEY_WRITE, nullptr, &scheme_key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }

  const wchar_t empty[] = L"";
  ::RegSetValueExW(scheme_key, L"URL Protocol", 0, REG_SZ,
                   reinterpret_cast<const BYTE *>(empty),
                   static_cast<DWORD>(sizeof(empty)));

  HKEY command_key;
  if (::RegCreateKeyExW(scheme_key, L"shell\\open\\command", 0, nullptr, 0,
                        KEY_WRITE, nullptr, &command_key,
                        nullptr) == ERROR_SUCCESS) {
    ::RegSetValueExW(
        command_key, nullptr, 0, REG_SZ,
        reinterpret_cast<const BYTE *>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(command_key);
  }

  ::RegCloseKey(scheme_key);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  RegisterUriScheme();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Shortir File", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
