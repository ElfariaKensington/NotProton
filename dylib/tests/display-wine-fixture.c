// Optional live CrossOver regression: actual Windows desktop and fullscreen client dimensions.
#include <windows.h>
#include <stdio.h>
static LRESULT CALLBACK procedure(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_PAINT) {
        PAINTSTRUCT ps; HDC dc = BeginPaint(window, &ps);
        RECT rect; GetClientRect(window, &rect);
        FillRect(dc, &rect, (HBRUSH)GetStockObject(DKGRAY_BRUSH));
        SetTextColor(dc, RGB(255,255,255)); SetBkMode(dc, TRANSPARENT);
        DrawTextA(dc,"NotProton fullscreen resolution test",-1,&rect,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
        EndPaint(window,&ps); return 0;
    }
    if (message == WM_TIMER) {
        RECT rect; GetClientRect(window,&rect);
        printf("desktop=%dx%d client=%ldx%ld\n",GetSystemMetrics(SM_CXSCREEN),GetSystemMetrics(SM_CYSCREEN),rect.right,rect.bottom);
        fflush(stdout);DestroyWindow(window);return 0;
    }
    if (message == WM_DESTROY) { PostQuitMessage(0);return 0; }
    return DefWindowProcA(window,message,wp,lp);
}
int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "--probe") == 0) {
        printf("desktop=%dx%d\n",GetSystemMetrics(SM_CXSCREEN),GetSystemMetrics(SM_CYSCREEN));return 0;
    }
    WNDCLASSA cls={0};cls.lpfnWndProc=procedure;cls.hInstance=GetModuleHandleA(NULL);cls.lpszClassName="NotProtonDisplayTest";RegisterClassA(&cls);
    HWND window=CreateWindowA(cls.lpszClassName,"NotProton fullscreen test",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,800,600,NULL,NULL,cls.hInstance,NULL);
    SetTimer(window,1,8000,NULL);
    MSG msg;while(GetMessageA(&msg,NULL,0,0)>0){TranslateMessage(&msg);DispatchMessageA(&msg);}return 0;
}
