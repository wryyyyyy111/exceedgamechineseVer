@echo off
setlocal
set "GODOT_EXE=D:\Godot\Godot_v4.4.1-stable_win64.exe\Godot_v4.4.1-stable_win64_console.exe"

if not exist "%GODOT_EXE%" (
    echo Missing Godot console binary: %GODOT_EXE%
    exit /b 1
)

"%GODOT_EXE%" --path "%~dp0" -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gexit