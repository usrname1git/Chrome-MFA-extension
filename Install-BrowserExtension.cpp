#define NOMINMAX
#include <windows.h>
#include <UIAutomation.h>
#include <bcrypt.h>
#include <wrl/client.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cwctype>
#include <filesystem>
#include <iostream>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using Element = ComPtr<IUIAutomationElement>;
using Clock = std::chrono::steady_clock;

namespace {
struct Failure : std::runtime_error { using std::runtime_error::runtime_error; };
struct UiChanged : Failure { UiChanged() : Failure("Browser interface changed during setup.") {} };
struct Cancelled {};
bool cancelled = false;
bool enable_requested = false;
constexpr int enable_button_id = 100;

void check(HRESULT result, const char* operation) {
    if (FAILED(result)) {
        if (result == UIA_E_ELEMENTNOTAVAILABLE) throw UiChanged{};
        std::ostringstream message;
        message << operation << " failed (0x" << std::hex
                << static_cast<unsigned long>(result) << ").";
        throw Failure(message.str());
    }
}

std::wstring full_path(const std::wstring& path) {
    const DWORD size = GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
    if (!size) throw Failure("Cannot resolve the installation path.");
    std::wstring result(size, L'\0');
    const DWORD length = GetFullPathNameW(path.c_str(), size, result.data(), nullptr);
    if (!length || length >= size) throw Failure("Cannot resolve the installation path.");
    result.resize(length);
    while (result.size() > 3 && result.back() == L'\\') result.pop_back();
    if (result.size() > 1 && result[1] == L':')
        result[0] = static_cast<wchar_t>(std::towupper(result[0]));
    return result;
}

bool equal_path(std::wstring a, std::wstring b) {
    if (a.rfind(L"~\\", 0) == 0) {
        std::array<wchar_t, 32768> home{};
        const DWORD length = GetEnvironmentVariableW(L"USERPROFILE", home.data(),
                                                     static_cast<DWORD>(home.size()));
        if (!length || length >= home.size()) return false;
        a = std::wstring(home.data()) + a.substr(1);
    }
    a = full_path(a);
    b = full_path(b);
    return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}

std::wstring extension_id(const std::wstring& path) {
    std::array<UCHAR, 32> hash{};
    const auto bytes = static_cast<ULONG>(path.size() * sizeof(wchar_t));
    check(BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0,
                    reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(path.data())),
                    bytes, hash.data(), static_cast<ULONG>(hash.size())),
          "Extension path hash");
    std::wstring result;
    for (size_t i = 0; i < 16; ++i) {
        result += static_cast<wchar_t>(L'a' + (hash[i] >> 4));
        result += static_cast<wchar_t>(L'a' + (hash[i] & 15));
    }
    return result;
}

LRESULT CALLBACK progress_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_COMMAND && LOWORD(wparam) == enable_button_id) {
        enable_requested = true;
        EnableWindow(GetDlgItem(window, enable_button_id), FALSE);
        return 0;
    }
    if (message == WM_CLOSE || (message == WM_COMMAND && LOWORD(wparam) == IDCANCEL)) {
        cancelled = true;
        ShowWindow(window, SW_HIDE);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

class Progress {
    HWND window_ = nullptr;
    HWND text_ = nullptr;
    HWND enable_ = nullptr;
public:
    explicit Progress(const std::wstring& browser) {
        WNDCLASSW cls{};
        cls.lpfnWndProc = progress_proc;
        cls.hInstance = GetModuleHandleW(nullptr);
        cls.lpszClassName = L"Autom8edVaultSetup";
        cls.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        cls.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        if (!RegisterClassW(&cls)) throw Failure("Cannot create the setup status window.");
        RECT area{};
        if (!SystemParametersInfoW(SPI_GETWORKAREA, 0, &area, 0))
            throw Failure("Cannot locate the interactive desktop.");
        window_ = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, cls.lpszClassName,
            (L"Autom8ed Vault setup - " + browser).c_str(), WS_OVERLAPPED | WS_CAPTION |
            WS_SYSMENU, std::max(area.left, area.right - 540),
            std::max(area.top, area.bottom - 190), 520, 170, nullptr, nullptr,
            cls.hInstance, nullptr);
        if (!window_) throw Failure("Cannot create the setup status window.");
        text_ = CreateWindowW(L"STATIC", L"", WS_CHILD | WS_VISIBLE, 16, 12, 480, 75,
                              window_, nullptr, cls.hInstance, nullptr);
        const auto button = CreateWindowW(L"BUTTON", L"Cancel setup", WS_CHILD |
            WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, 350, 96, 145, 26, window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDCANCEL)), cls.hInstance, nullptr);
        enable_ = CreateWindowW(L"BUTTON", L"Enable Developer mode and install",
            WS_CHILD | WS_TABSTOP | BS_PUSHBUTTON, 16, 96, 270, 26, window_,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(enable_button_id)), cls.hInstance, nullptr);
        if (!text_ || !button || !enable_) throw Failure("Cannot create the setup controls.");
        const auto font = GetStockObject(DEFAULT_GUI_FONT);
        SendMessageW(text_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        SendMessageW(enable_, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
        ShowWindow(window_, SW_SHOWNOACTIVATE);
    }
    ~Progress() { if (window_) DestroyWindow(window_); }
    void status(const std::wstring& message) {
        SetWindowTextW(text_, message.c_str());
        std::wcout << message << std::endl;
    }
    void offer_enable() { ShowWindow(enable_, SW_SHOWNOACTIVATE); }
    void hide_enable() { ShowWindow(enable_, SW_HIDE); }
    void pump() {
        MSG message{};
        while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        if (cancelled) throw Cancelled{};
    }
};

class Ui {
    ComPtr<IUIAutomation> automation_;
public:
    Ui() {
        check(CoCreateInstance(CLSID_CUIAutomation8, nullptr, CLSCTX_INPROC_SERVER,
                               IID_PPV_ARGS(&automation_)), "Windows accessibility");
        ComPtr<IUIAutomation2> timed;
        check(automation_.As(&timed), "Accessibility timeouts");
        check(timed->put_ConnectionTimeout(3000), "Accessibility connection timeout");
        check(timed->put_TransactionTimeout(3000), "Accessibility operation timeout");
    }
    Element root(HWND window) {
        Element result;
        check(automation_->ElementFromHandle(window, &result), "Browser window access");
        return result;
    }
    Element find(const Element& parent, PROPERTYID property, const VARIANT& value) {
        if (!parent) return {};
        ComPtr<IUIAutomationCondition> condition;
        check(automation_->CreatePropertyCondition(property, value, &condition),
              "Accessibility selector");
        Element result;
        check(parent->FindFirst(TreeScope_Subtree, condition.Get(), &result),
              "Browser control lookup");
        return result;
    }
    Element id(const Element& parent, const std::wstring& id_value) {
        VARIANT value{};
        value.vt = VT_BSTR;
        value.bstrVal = SysAllocString(id_value.c_str());
        if (!value.bstrVal) throw std::bad_alloc{};
        Element result;
        try { result = find(parent, UIA_AutomationIdPropertyId, value); }
        catch (...) { VariantClear(&value); throw; }
        VariantClear(&value);
        return result;
    }
    Element named(const Element& parent, const std::wstring& name) {
        VARIANT value{};
        value.vt = VT_BSTR;
        value.bstrVal = SysAllocString(name.c_str());
        if (!value.bstrVal) throw std::bad_alloc{};
        Element result;
        try { result = find(parent, UIA_NamePropertyId, value); }
        catch (...) { VariantClear(&value); throw; }
        VariantClear(&value);
        return result;
    }
    Element property(const Element& parent, PROPERTYID property_id, LONG number) {
        VARIANT value{};
        value.vt = VT_I4;
        value.lVal = number;
        return find(parent, property_id, value);
    }
    Element selected_tab(HWND window) {
        VARIANT selected{}, type{};
        selected.vt = VT_BOOL;
        selected.boolVal = VARIANT_TRUE;
        type.vt = VT_I4;
        type.lVal = UIA_TabItemControlTypeId;
        ComPtr<IUIAutomationCondition> selected_condition, type_condition, condition;
        check(automation_->CreatePropertyCondition(UIA_SelectionItemIsSelectedPropertyId,
              selected, &selected_condition), "Selected browser tab");
        check(automation_->CreatePropertyCondition(UIA_ControlTypePropertyId,
              type, &type_condition), "Browser tab type");
        check(automation_->CreateAndCondition(selected_condition.Get(), type_condition.Get(),
              &condition), "Browser tab selector");
        Element tab;
        check(root(window)->FindFirst(TreeScope_Descendants, condition.Get(), &tab),
              "Selected browser tab lookup");
        if (!tab) throw Failure("The browser setup tab is not accessible.");
        return tab;
    }
    void select_tab(const Element& tab) {
        ComPtr<IUIAutomationSelectionItemPattern> pattern;
        check(tab->GetCurrentPatternAs(UIA_SelectionItemPatternId, IID_PPV_ARGS(&pattern)),
              "Browser setup tab");
        check(pattern->Select(), "Activate browser setup tab");
    }
    std::wstring name(const Element& element) {
        BSTR result = nullptr;
        check(element->get_CurrentName(&result), "Browser control text");
        const std::wstring text = result ? result : L"";
        SysFreeString(result);
        return text;
    }
    bool enabled(const Element& element) {
        BOOL result = FALSE;
        check(element->get_CurrentIsEnabled(&result), "Browser control state");
        return result != FALSE;
    }
    Element switch_element(const Element& host) {
        VARIANT value{};
        value.vt = VT_BOOL;
        value.boolVal = VARIANT_TRUE;
        const auto element = find(host, UIA_IsTogglePatternAvailablePropertyId, value);
        if (!element) throw Failure("Browser switch is not accessible.");
        return element;
    }
    ToggleState toggle(const Element& host) {
        const auto element = switch_element(host);
        ComPtr<IUIAutomationTogglePattern> pattern;
        check(element->GetCurrentPatternAs(UIA_TogglePatternId, IID_PPV_ARGS(&pattern)),
              "Browser switch access");
        ToggleState state = ToggleState_Indeterminate;
        check(pattern->get_CurrentToggleState(&state), "Browser switch state");
        return state;
    }
    void enable(const Element& host) {
        const auto element = switch_element(host);
        if (!enabled(element)) throw Failure("The browser switch is disabled by policy.");
        ComPtr<IUIAutomationTogglePattern> pattern;
        check(element->GetCurrentPatternAs(UIA_TogglePatternId, IID_PPV_ARGS(&pattern)),
              "Browser switch access");
        ToggleState state = ToggleState_Indeterminate;
        check(pattern->get_CurrentToggleState(&state), "Browser switch state");
        if (state == ToggleState_Off) check(pattern->Toggle(), "Enable browser switch");
        else if (state != ToggleState_On) throw Failure("Browser switch state is unknown.");
    }
    bool contains_name(const Element& parent, const std::wstring& needle) {
        if (!parent) return false;
        ComPtr<IUIAutomationCondition> condition;
        check(automation_->CreateTrueCondition(&condition), "Browser text selector");
        ComPtr<IUIAutomationElementArray> elements;
        check(parent->FindAll(TreeScope_Descendants, condition.Get(), &elements),
              "Browser text lookup");
        int length = 0;
        check(elements->get_Length(&length), "Browser text count");
        for (int i = 0; i < length; ++i) {
            Element element;
            check(elements->GetElement(i, &element), "Browser text element");
            if (name(element).find(needle) != std::wstring::npos) return true;
        }
        return false;
    }
    bool contains_path_link(const Element& parent, const std::wstring& path) {
        VARIANT value{};
        value.vt = VT_I4;
        value.lVal = UIA_HyperlinkControlTypeId;
        ComPtr<IUIAutomationCondition> condition;
        check(automation_->CreatePropertyCondition(UIA_ControlTypePropertyId, value, &condition),
              "Extension path selector");
        ComPtr<IUIAutomationElementArray> links;
        check(parent->FindAll(TreeScope_Descendants, condition.Get(), &links),
              "Extension path links");
        int length = 0;
        check(links->get_Length(&length), "Extension path link count");
        for (int i = 0; i < length; ++i) {
            Element link;
            check(links->GetElement(i, &link), "Extension path link");
            const auto text = name(link);
            if ((text.rfind(L"~\\", 0) == 0 || text.rfind(L"\\\\", 0) == 0 ||
                 (text.size() > 2 && text[1] == L':')) && equal_path(text, path))
                return true;
        }
        return false;
    }
    void click(const Element& host) {
        const auto button = property(host, UIA_ControlTypePropertyId, UIA_ButtonControlTypeId);
        if (!button || !enabled(button)) throw Failure("Browser action is disabled or inaccessible.");
        ComPtr<IUIAutomationInvokePattern> pattern;
        check(button->GetCurrentPatternAs(UIA_InvokePatternId, IID_PPV_ARGS(&pattern)),
              "Browser button access");
        check(pattern->Invoke(), "Browser button");
    }
    void navigate(HWND window, const std::wstring& url) {
        const auto address = id(root(window), L"view_1012");
        if (!address) throw Failure("The browser address bar is unavailable. Select a browser profile first.");
        ComPtr<IUIAutomationValuePattern> pattern;
        check(address->GetCurrentPatternAs(UIA_ValuePatternId, IID_PPV_ARGS(&pattern)),
              "Browser address bar");
        check(address->SetFocus(), "Browser focus");
        const BSTR destination = SysAllocString(url.c_str());
        if (!destination) throw std::bad_alloc{};
        const HRESULT navigation = pattern->SetValue(destination);
        SysFreeString(destination);
        check(navigation, "Browser navigation");
        DWORD_PTR result = 0;
        if (!SendMessageTimeoutW(window, WM_KEYDOWN, VK_RETURN, 1, SMTO_ABORTIFHUNG,
                                 3000, &result) ||
            !SendMessageTimeoutW(window, WM_KEYUP, VK_RETURN,
                                 (1LL << 31) | (1LL << 30) | 1,
                                 SMTO_ABORTIFHUNG, 3000, &result))
            throw Failure("The browser did not accept navigation.");
    }
    Element document(HWND window) {
        const auto browser_root = root(window);
        const auto address = id(browser_root, L"view_1012");
        if (!address) return {};
        ComPtr<IUIAutomationValuePattern> pattern;
        check(address->GetCurrentPatternAs(UIA_ValuePatternId, IID_PPV_ARGS(&pattern)),
              "Browser location");
        BSTR value = nullptr;
        check(pattern->get_CurrentValue(&value), "Browser location");
        const std::wstring url = value ? value : L"";
        SysFreeString(value);
        const std::array<std::wstring, 3> origins{
            L"chrome://extensions", L"brave://extensions", L"edge://extensions"};
        bool matches = false;
        for (const auto& origin : origins) {
            if (url == origin || url.rfind(origin + L"/", 0) == 0 ||
                url.rfind(origin + L"?", 0) == 0) matches = true;
        }
        if (!matches) return {};
        return id(browser_root, L"RootWebArea");
    }
    void reject_load_error(const Element& doc) {
        if (id(doc, L"load-error") || id(doc, L"dialog"))
            throw Failure("Browser rejected the extension. See the visible load-error dialog for details.");
    }
};

std::wstring image_path(HWND window) {
    DWORD pid = 0;
    GetWindowThreadProcessId(window, &pid);
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process) return {};
    std::array<wchar_t, 32768> buffer{};
    DWORD size = static_cast<DWORD>(buffer.size());
    const BOOL ok = QueryFullProcessImageNameW(process, 0, buffer.data(), &size);
    CloseHandle(process);
    return ok ? std::wstring(buffer.data(), size) : std::wstring{};
}

struct Windows {
    std::wstring exe;
    std::set<HWND> handles;
};
BOOL CALLBACK enumerate_browser(HWND window, LPARAM data) {
    auto& windows = *reinterpret_cast<Windows*>(data);
    wchar_t name[64]{};
    GetClassNameW(window, name, 64);
    if (IsWindowVisible(window) && std::wstring(name) == L"Chrome_WidgetWin_1") {
        const auto image = image_path(window);
        if (!image.empty() && equal_path(image, windows.exe)) windows.handles.insert(window);
    }
    return TRUE;
}
std::set<HWND> browser_windows(const std::wstring& exe) {
    Windows windows{exe, {}};
    if (!EnumWindows(enumerate_browser, reinterpret_cast<LPARAM>(&windows)))
        throw Failure("Cannot enumerate browser windows.");
    return windows.handles;
}

HWND folder_picker(HWND window) {
    HWND popup = GetWindow(window, GW_ENABLEDPOPUP);
    wchar_t name[64]{};
    GetClassNameW(popup, name, 64);
    if (popup != window && std::wstring(name) == L"#32770" &&
        GetWindow(popup, GW_OWNER) == window) return popup;
    return nullptr;
}

void submit_folder(HWND dialog, const std::wstring& path) {
    const HWND input = GetDlgItem(dialog, 1152);
    const HWND confirm = GetDlgItem(dialog, IDOK);
    wchar_t input_class[64]{}, button_class[64]{};
    GetClassNameW(input, input_class, 64);
    GetClassNameW(confirm, button_class, 64);
    if (std::wstring(input_class) != L"Edit" ||
        std::wstring(button_class) != L"Button" || !IsWindowEnabled(confirm))
        throw Failure("The browser folder picker is not accessible. No installation was confirmed.");
    DWORD_PTR result = 0;
    if (!SendMessageTimeoutW(input, WM_SETTEXT, 0, reinterpret_cast<LPARAM>(path.c_str()),
                             SMTO_ABORTIFHUNG, 3000, &result) || !result)
        throw Failure("Cannot enter the extension directory.");
    if (!SendMessageTimeoutW(confirm, BM_CLICK, 0, 0, SMTO_ABORTIFHUNG, 3000, &result))
        throw Failure("The folder picker did not accept the extension directory.");
}

template<class Predicate>
void wait_for(Progress& progress, Clock::time_point deadline, HWND window,
              const char* error, Predicate predicate) {
    bool reported_change = false;
    while (Clock::now() < deadline) {
        progress.pump();
        if (window && !IsWindow(window)) throw Cancelled{};
        try { if (predicate()) return; }
        catch (const UiChanged&) {
            if (!reported_change) {
                std::wcout << L"Browser interface refreshed; retrying." << std::endl;
                reported_change = true;
            }
        }
        Sleep(200);
    }
    throw Failure(error);
}

struct Options {
    std::wstring exe, path, name, version, profile;
    HWND window = nullptr;
    int seconds = 600;
};
Options options(int argc, wchar_t** argv) {
    Options result;
    std::set<std::wstring> seen;
    for (int i = 1; i < argc; i += 2) {
        if (i + 1 >= argc || !seen.insert(argv[i]).second)
            throw Failure("Invalid or duplicate installer arguments.");
        const std::wstring key = argv[i], value = argv[i + 1];
        size_t consumed = 0;
        if (key == L"--browser") result.exe = value;
        else if (key == L"--path") result.path = value;
        else if (key == L"--name") result.name = value;
        else if (key == L"--version") result.version = value;
        else if (key == L"--user-data-dir") result.profile = full_path(value);
        else if (key == L"--window") {
            result.window = reinterpret_cast<HWND>(std::stoull(value, &consumed));
            if (consumed != value.size() || !result.window) throw Failure("Invalid browser window.");
        } else if (key == L"--timeout") {
            result.seconds = std::stoi(value, &consumed);
            if (consumed != value.size() || result.seconds < 1 || result.seconds > 3600)
                throw Failure("Timeout must be between 1 and 3600 seconds.");
        } else throw Failure("Unknown installer argument.");
    }
    if (result.exe.empty() || result.path.empty() || result.name.empty() || result.version.empty())
        throw Failure("Browser, extension path, name and version are required.");
    result.exe = full_path(result.exe);
    result.path = full_path(result.path);
    if (!std::filesystem::is_regular_file(result.exe) ||
        !std::filesystem::is_regular_file(std::filesystem::path(result.path) / L"manifest.json"))
        throw Failure("Browser executable or extension manifest is missing.");
    const auto filename = std::filesystem::path(result.exe).filename().wstring();
    if (filename != L"chrome.exe" && filename != L"msedge.exe" && filename != L"brave.exe")
        throw Failure("Select Chrome, Edge or Brave.");
    if (result.window && !equal_path(image_path(result.window), result.exe))
        throw Failure("The specified window does not belong to the selected browser.");
    return result;
}

void install(Options config) {
    Ui ui;
    const auto filename = std::filesystem::path(config.exe).filename().wstring();
    const std::wstring browser = filename == L"msedge.exe" ? L"Edge" :
                                 filename == L"brave.exe" ? L"Brave" : L"Chrome";
    Progress progress(browser);
    const auto deadline = Clock::now() + std::chrono::seconds(config.seconds);
    if (!config.window) {
        const auto before = browser_windows(config.exe);
        std::wstring command = L"\"" + config.exe + L"\" --new-window about:blank";
        if (!config.profile.empty()) {
            if (config.profile.find(L'"') != std::wstring::npos)
                throw Failure("Invalid browser profile path.");
            command += L" --user-data-dir=\"" + config.profile +
                L"\" --no-first-run --disable-default-apps --disable-background-networking";
        }
        STARTUPINFOW startup{};
        startup.cb = sizeof(startup);
        PROCESS_INFORMATION process{};
        progress.status(L"Opening extension setup. Select your browser profile if asked.");
        if (!CreateProcessW(config.exe.c_str(), command.data(), nullptr, nullptr, FALSE,
                            0, nullptr, nullptr, &startup, &process))
            throw Failure("The selected browser could not be started.");
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        wait_for(progress, deadline, nullptr, "No browser setup window appeared.", [&] {
            std::vector<HWND> candidates;
            for (const auto window : browser_windows(config.exe)) {
                if (!before.count(window) && ui.id(ui.root(window), L"view_1012"))
                    candidates.push_back(window);
            }
            if (candidates.size() > 1)
                throw Failure("Multiple new browser windows appeared. Close them and retry setup.");
            if (candidates.empty()) return false;
            config.window = candidates[0];
            return true;
        });
    }
    ui.navigate(config.window, L"chrome://extensions/");
    auto last_navigation = Clock::now();
    bool reported_navigation_retry = false;
    Element dev;
    const auto page_deadline = std::min(deadline, Clock::now() + std::chrono::seconds(30));
    wait_for(progress, page_deadline, config.window, "The extensions page did not become accessible.", [&] {
        dev = ui.id(ui.document(config.window), L"devMode");
        if (!dev && Clock::now() - last_navigation > std::chrono::seconds(2)) {
            if (!reported_navigation_retry) {
                std::wcout << L"Waiting for browser startup; reopening extension settings." << std::endl;
                reported_navigation_retry = true;
            }
            ui.navigate(config.window, L"chrome://extensions/");
            last_navigation = Clock::now();
        }
        return static_cast<bool>(dev);
    });
    const auto setup_tab = ui.selected_tab(config.window);
    if (!ui.enabled(ui.switch_element(dev)))
        throw Failure("Developer mode is disabled by browser policy.");
    if (ui.toggle(dev) != ToggleState_On) {
        progress.status(L"Developer mode is not enabled in " + browser +
            L". Click 'Enable Developer mode and install' to approve enabling it, "
            L"or enable it yourself on the extensions page. Setup will continue automatically.");
        progress.offer_enable();
        wait_for(progress, deadline, config.window, "Timed out waiting for Developer mode.", [&] {
            dev = ui.id(ui.document(config.window), L"devMode");
            if (dev && enable_requested) {
                ui.enable(dev);
                enable_requested = false;
            }
            return dev && ui.toggle(dev) == ToggleState_On;
        });
        progress.hide_enable();
    }
    progress.status(L"Installing the extension. Please leave this setup window open.");
    Element load;
    wait_for(progress, deadline, config.window, "Load unpacked is unavailable or blocked by browser policy.", [&] {
        load = ui.id(ui.document(config.window), L"loadUnpacked");
        return static_cast<bool>(load);
    });
    ui.click(load);
    HWND dialog = nullptr;
    wait_for(progress, deadline, config.window, "The extension folder picker did not open.", [&] {
        dialog = folder_picker(config.window);
        return dialog != nullptr;
    });
    submit_folder(dialog, config.path);
    wait_for(progress, deadline, config.window, "The extension folder picker did not finish.", [&] {
        return !IsWindow(dialog);
    });
    const auto id = extension_id(config.path);
    const auto verification_deadline = std::min(deadline, Clock::now() + std::chrono::seconds(45));
    wait_for(progress, verification_deadline, config.window, "The browser did not register the extension. "
             "Inspect the extensions page for an error.", [&] {
        ui.select_tab(setup_tab);
        const auto doc = ui.document(config.window);
        ui.reject_load_error(doc);
        return ui.contains_name(doc, id);
    });
    ui.navigate(config.window, L"chrome://extensions/?id=" + id);
    wait_for(progress, verification_deadline, config.window, "The browser did not confirm the extension path, "
             "version and enabled state. Inspect the extensions page for an error.", [&] {
        const auto doc = ui.document(config.window);
        const auto name = ui.id(doc, L"name");
        const auto toggle = ui.id(doc, L"enableToggle");
        if (!doc || !name || !toggle || ui.name(name) != config.name ||
            !ui.named(doc, config.version) || !ui.contains_path_link(doc, config.path)) return false;
        if (ui.toggle(toggle) != ToggleState_On) {
            ui.enable(toggle);
            return false;
        }
        return true;
    });
    progress.status(L"Verified installed and enabled: " + config.name + L" " + config.version);
    std::wcout << L"Extension ID: " << id << std::endl;
}
}

int wmain(int argc, wchar_t** argv) {
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(initialized)) {
        std::cerr << "Windows accessibility initialization failed.\n";
        return 1;
    }
    int result = 0;
    try { install(options(argc, argv)); }
    catch (const Cancelled&) {
        std::cerr << "Setup cancelled; installation was not confirmed.\n";
        result = 130;
    } catch (const std::exception& error) {
        std::cerr << "Setup failed: " << error.what() << "\n";
        result = 1;
    }
    CoUninitialize();
    return result;
}
