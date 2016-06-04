:: run32.bat
@echo off

:: add Adafruit params to parameters.txt
start /wait clockGenParams

:: setup environment
call "D:\Program Files (x86)\XMOS\Community_14.1.2\Community_14.2.0\SetEnv.bat"

:: run slave binaries
FOR \l %%x IN (2,1,32) DO (
  xrun --id (%%x - 2) %%x\slave.xe
)

:: run master binary
  xrun --id 31 --io 1\master.xe
cmd /k