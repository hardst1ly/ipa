// Расписание уроков — обёртка для Windows.
// Показывает www/ (встроенный в exe как один HTML-файл) в окне Microsoft Edge WebView2.
// Собирается из Linux: zig c++ -target x86_64-windows-gnu (см. standalone/build.sh).

#include "webview/webview.h"

#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>

#include <string>

#include "app_html.h" // генерируется при сборке: APP_HTML[], APP_HTML_LEN

namespace {

std::wstring known_folder(int csidl) {
  wchar_t path[MAX_PATH] = {0};
  if (SUCCEEDED(SHGetFolderPathW(nullptr, csidl, nullptr, 0, path))) {
    return path;
  }
  return L".";
}

std::string to_utf8(const std::wstring &w) {
  if (w.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), nullptr, 0,
                              nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), (int)w.size(), &s[0], n, nullptr,
                      nullptr);
  return s;
}

// C:\Users\Имя\... -> file:///C:/Users/%D0%98.../
std::string file_url(const std::wstring &path) {
  std::string utf8 = to_utf8(path);
  std::string url = "file:///";
  const char *hex = "0123456789ABCDEF";
  for (unsigned char c : utf8) {
    if (c == '\\') {
      url += '/';
    } else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
               (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' ||
               c == '~' || c == '/' || c == ':') {
      url += (char)c;
    } else {
      url += '%';
      url += hex[c >> 4];
      url += hex[c & 15];
    }
  }
  return url;
}

bool write_file(const std::wstring &path, const unsigned char *data,
                size_t size) {
  HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  BOOL ok = WriteFile(h, data, (DWORD)size, &written, nullptr);
  CloseHandle(h);
  return ok && written == size;
}

void fail(const wchar_t *text) {
  int r = MessageBoxW(nullptr, text, L"Расписание уроков",
                      MB_ICONERROR | MB_YESNO);
  if (r == IDYES) {
    ShellExecuteW(nullptr, L"open",
                  L"https://developer.microsoft.com/microsoft-edge/webview2/",
                  nullptr, nullptr, SW_SHOWNORMAL);
  }
}

} // namespace

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
  // Все данные — в %LOCALAPPDATA%\Raspisanie (не зависит от того, где лежит exe)
  std::wstring base = known_folder(CSIDL_LOCAL_APPDATA) + L"\\Raspisanie";
  std::wstring app_dir = base + L"\\app";
  CreateDirectoryW(base.c_str(), nullptr);
  CreateDirectoryW(app_dir.c_str(), nullptr);

  // Профиль WebView2 (там же хранится localStorage с расписанием)
  SetEnvironmentVariableW(L"WEBVIEW2_USER_DATA_FOLDER",
                          (base + L"\\WebView2").c_str());

  std::wstring index = app_dir + L"\\index.html";
  if (!write_file(index, APP_HTML, APP_HTML_LEN)) {
    MessageBoxW(nullptr, L"Не удалось записать файлы приложения.",
                L"Расписание уроков", MB_ICONERROR);
    return 1;
  }

  try {
    webview::webview w(false, nullptr);
    w.set_title("Расписание уроков");
    w.set_size(1280, 820, WEBVIEW_HINT_NONE);
    w.set_size(380, 560, WEBVIEW_HINT_MIN);
    w.navigate(file_url(index));
    w.run();
  } catch (const webview::exception &) {
    fail(L"Для работы нужен компонент Microsoft Edge WebView2 Runtime.\n"
         L"В Windows 11 он уже есть, в Windows 10 его нужно установить.\n\n"
         L"Открыть страницу загрузки?");
    return 1;
  }
  return 0;
}
