@echo off

FOR /L %%x IN (2,1,32) DO (
  xcopy /y "slave.xe" "%~dp0\%%x"
)