@echo off
REM ****************************************************************************
REM Vivado (TM) v2019.1 (64-bit)
REM
REM Filename    : simulate.bat
REM Simulator   : Xilinx Vivado Simulator
REM Description : Script for simulating the design by launching the simulator
REM
REM Generated by Vivado on Wed Nov 23 20:33:08 +0000 2022
REM SW Build 2552052 on Fri May 24 14:49:42 MDT 2019
REM
REM Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
REM
REM usage: simulate.bat
REM
REM ****************************************************************************
echo "xsim gameAndReg32x32_TB_behav -key {Behavioral:sim_1:Functional:gameAndReg32x32_TB} -tclbatch gameAndReg32x32_TB.tcl -view C:/Vicilog/game/game/testbench/gameAndReg32x32_TB_behav.wcfg -log simulate.log"
call xsim  gameAndReg32x32_TB_behav -key {Behavioral:sim_1:Functional:gameAndReg32x32_TB} -tclbatch gameAndReg32x32_TB.tcl -view C:/Vicilog/game/game/testbench/gameAndReg32x32_TB_behav.wcfg -log simulate.log
if "%errorlevel%"=="0" goto SUCCESS
if "%errorlevel%"=="1" goto END
:END
exit 1
:SUCCESS
exit 0
