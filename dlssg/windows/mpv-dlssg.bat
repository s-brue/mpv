@echo off
rem mpv with NVIDIA DLSS Frame Generation. Drop a video on this file, or run
rem   mpv-dlssg.bat video.mkv
rem ModernZ interface, unless the configuration already has one of its own
set "UI=--script="%~dp0modernz.lua" --osd-fonts-dir="%~dp0fonts""
for %%c in ("%APPDATA%\mpv" "%~dp0portable_config") do (
    if exist "%%~c\scripts\*osc*" set "UI="
    if exist "%%~c\scripts\modern*" set "UI="
)
if "%MPV_DLSSG_OSC%"=="no" set "UI="
rem thumbnails, unless the configuration has its own thumbfast
set "THUMBS=--script="%~dp0thumbfast.lua""
for %%c in ("%APPDATA%\mpv" "%~dp0portable_config") do (
    if exist "%%~c\scripts\*thumbfast*" set "THUMBS="
)
if "%MPV_DLSSG_THUMBNAILS%"=="no" set "THUMBS="
"%~dp0mpv.exe" --gpu-api=vulkan --hwdec=auto-safe --script="%~dp0dlssg.lua" %UI% %THUMBS% %*
