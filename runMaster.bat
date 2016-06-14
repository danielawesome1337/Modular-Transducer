:: runMaster.bat
@echo off

:: add Adafruit params to parameters.txt
start /wait clockGenParams.exe

:: setup environment
call "C:\Program Files (x86)\XMOS\xTIMEcomposer\Community_14.1.2\SetEnv.bat"

:: run binary.xe
xrun --id 0 --io 1\master.xe
cmd /k
