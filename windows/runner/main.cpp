#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"
// #include <protocol_handler_windows/protocol_handler_windows_plugin_c_api.h>

bool SendAppLinkToInstance(const std::wstring &title)
{
  // Find our exact window
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());

  if (hwnd)
  {
    // Dispatch new link to current window
    SendAppLink(hwnd);

    // (Optional) Restore our window to front in same state
    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &place);

    switch (place.showCmd)
    {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
    }

    SetWindowPos(0, HWND_TOP, 0, 0, 0, 0, SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    SetForegroundWindow(hwnd);
    // END (Optional) Restore

    // Window has been found, don't create another one.
    return true;
  }

  return false;
}

// Шлюпка: режим VPN требует прав администратора. Обычный запуск (ярлык, двойной щелчок)
// передаётся задаче планировщика \RescueBoat\Start (создаёт установщик,
// windows/packaging/rescueboat-tasks.ps1): она запускает программу с правами без окна UAC.
// Задачи нет (портативная версия) — программа стартует как обычно.
static bool IsElevated()
{
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token))
    return false;
  TOKEN_ELEVATION elevation = {};
  DWORD size = 0;
  BOOL ok = GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size);
  CloseHandle(token);
  return ok && elevation.TokenIsElevated;
}

static bool HasArgument(const wchar_t *command_line, const wchar_t *arg)
{
  return command_line != nullptr && wcsstr(command_line, arg) != nullptr;
}

static bool RunStartTask()
{
  wchar_t cmd[] = L"schtasks.exe /Run /TN \"\\RescueBoat\\Start\"";
  STARTUPINFOW si = {sizeof(si)};
  PROCESS_INFORMATION pi = {};
  if (!CreateProcessW(nullptr, cmd, nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi))
    return false;
  WaitForSingleObject(pi.hProcess, 10000);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return code == 0;
}

// Шлюпка: заголовок окна (по нему второй запуск находит первый).
static const wchar_t kAppTitle[] = L"\u0428\u043b\u044e\u043f\u043a\u0430 \u0441\u043f\u0430\u0441\u0435\u043d\u0438\u044f";

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{

  // Replace "example" with the generated title found as parameter of `window.Create` in this file.
  // You may ignore the result if you need to create another window.
  if (SendAppLinkToInstance(kAppTitle))
  {
    return EXIT_SUCCESS;
  }

  // --from-task: запущены задачей, второй раз не передаём (и не зацикливаемся, если у
  // пользователя нет прав администратора). Ссылки rescueboat:// задача не передаст.
  if (!HasArgument(command_line, L"--from-task") && !HasArgument(command_line, L"://") &&
      !IsElevated() && RunStartTask())
  {
    return EXIT_SUCCESS;
  }

  HANDLE hMutexInstance = CreateMutex(NULL, TRUE, L"RescueBoatMutex");
  HWND handle = FindWindowW(NULL, kAppTitle);

  if (GetLastError() == ERROR_ALREADY_EXISTS)
  {
    flutter::DartProject project(L"data");
    std::vector<std::string> command_line_arguments = GetCommandLineArguments();
    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
    FlutterWindow window(project);
    if (window.SendAppLinkToInstance(kAppTitle))
    {
      return false;
    }

    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(handle, &place);
    ShowWindow(handle, SW_NORMAL);
    return 0;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
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
  if (!window.Create(kAppTitle, origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(hMutexInstance);
  return EXIT_SUCCESS;
}
