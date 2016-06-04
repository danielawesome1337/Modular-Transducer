:: runMaster.bat
@echo off

:: add Adafruit params to parameters.txt
start /wait clockGenParams

:: setup environment
call "D:\Program Files (x86)\XMOS\Community_14.1.2\Community_14.2.0\SetEnv.bat"

:: run binary.xe
xrun --id 0 --io 1\master.xe
cmd /k