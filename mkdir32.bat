:: mkdir32.bat
@echo off

FOR /L %%x IN (1,1,32) DO (
  if not exist "%%x" mkdir "%%x"
)
