@echo off
rem mpv with NVIDIA DLSS Frame Generation. Drop a video on this file, or run
rem   mpv-dlssg.bat video.mkv
"%~dp0mpv.exe" --gpu-api=vulkan --hwdec=auto-safe --script="%~dp0dlssg.lua" %*
