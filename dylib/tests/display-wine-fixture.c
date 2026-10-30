// Optional live CrossOver regression: actual Windows desktop and fullscreen client dimensions.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <GL/gl.h>
static HDC gameDC;
static HGLRC gameGL;
static DWORD WINAPI dismiss_warning(void *unused) {
    (void)unused;
    for (int i=0;i<100;i++) {
        HWND dialog=FindWindowA("#32770","NotProton driver warning");
        if (dialog) { Sleep(750);RECT rect;GetWindowRect(dialog,&rect);
            printf("dialog=%ldx%ld\n",rect.right-rect.left,rect.bottom-rect.top);fflush(stdout);
            if (getenv("NP_TEST_NATIVE_DIALOG_INPUT")) {
                RECT button;GetWindowRect(GetDlgItem(dialog,IDNO),&button);
                POINT client={0,0};ClientToScreen(dialog,&client);
                printf("buttonLocal=%ld,%ld\n",(button.left+button.right)/2-client.x,(button.top+button.bottom)/2-client.y);fflush(stdout);
                Sleep(10000);
                if (!IsWindow(dialog)) return 0;
                puts("input=FAILED");fflush(stdout);
            }
            SendMessageA(dialog,WM_COMMAND,IDNO,0);return 0; }
        Sleep(50);
    }
    return 1;
}
static LRESULT CALLBACK procedure(HWND window, UINT message, WPARAM wp, LPARAM lp) {
    if (message == WM_PAINT) {
        PAINTSTRUCT ps; HDC dc = BeginPaint(window, &ps);
        RECT rect; GetClientRect(window, &rect);
        FillRect(dc, &rect, (HBRUSH)GetStockObject(DKGRAY_BRUSH));
        SetTextColor(dc, RGB(255,255,255)); SetBkMode(dc, TRANSPARENT);
        DrawTextA(dc,"NotProton fullscreen resolution test",-1,&rect,DT_CENTER|DT_VCENTER|DT_SINGLELINE);
        EndPaint(window,&ps); return 0;
    }
    if (message == WM_TIMER && wp == 2) {
        glClearColor(.04f,.04f,.04f,1.f);glClear(GL_COLOR_BUFFER_BIT);SwapBuffers(gameDC);return 0;
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
    CreateThread(NULL,0,dismiss_warning,NULL,0,NULL);
    int answer=MessageBoxA(NULL,"The installed graphics driver has known issues.\nPlease choose a different rendering API.\n\n"
        "Installed driver: compatibility mode\nRecommended driver: newer version\n\n"
        "This warning must stay a normal dialog.\nIt must not enter a fullscreen Space.\n"
        "Its text must remain readable.\nIts buttons must retain their normal positions.\n\n"
        "Continue launching the game?", "NotProton driver warning", MB_YESNO|MB_ICONWARNING);
    printf("inputResult=%d\n",answer);fflush(stdout);
    WNDCLASSA cls={0};cls.lpfnWndProc=procedure;cls.hInstance=GetModuleHandleA(NULL);cls.lpszClassName="NotProtonDisplayTest";RegisterClassA(&cls);
    HWND window=CreateWindowA(cls.lpszClassName,"NotProton fullscreen test",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,800,600,NULL,NULL,cls.hInstance,NULL);
    gameDC=GetDC(window);
    PIXELFORMATDESCRIPTOR pfd={0};pfd.nSize=sizeof pfd;pfd.nVersion=1;
    pfd.dwFlags=PFD_DRAW_TO_WINDOW|PFD_SUPPORT_OPENGL|PFD_DOUBLEBUFFER;
    pfd.iPixelType=PFD_TYPE_RGBA;pfd.cColorBits=24;pfd.cDepthBits=24;
    int format=ChoosePixelFormat(gameDC,&pfd);
    if (!format||!SetPixelFormat(gameDC,format,&pfd)||(gameGL=wglCreateContext(gameDC))==NULL||!wglMakeCurrent(gameDC,gameGL))return 4;
    SetTimer(window,1,8000,NULL);SetTimer(window,2,30,NULL);
    MSG msg;while(GetMessageA(&msg,NULL,0,0)>0){TranslateMessage(&msg);DispatchMessageA(&msg);}return 0;
}
