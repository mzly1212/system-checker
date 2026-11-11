@echo off
chcp 65001 >nul
title 电脑全面体检
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ComputerHealthCheck.ps1" %*
echo.
pause
