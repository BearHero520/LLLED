@echo off
echo 正在推送修复版本到GitHub...

cd /d "e:\工作台\LLLED"

REM 添加所有修改的文件
git add .

REM 提交修改
git commit -m "修复语法错误 - 解决esac语法问题"

REM 推送到GitHub
git push origin main

echo.
echo 修复版本已推送到GitHub
echo 用户现在可以重新运行一键安装命令：
echo.
echo wget -O quick_install.sh https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh ^&^& chmod +x quick_install.sh ^&^& sudo ./quick_install.sh
echo.
pause
