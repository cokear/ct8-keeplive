#!/bin/bash

# 设置超时时间（秒）
SSH_TIMEOUT=15

# 保活命令（根据实际需求调整）
KEEPALIVE_CMD="date"

AUTOUPDATE=${AUTOUPDATE:-Y}
SENDTYPE=${SENDTYPE:-null}
TELEGRAM_TOKEN=${TELEGRAM_TOKEN:-null}
TELEGRAM_USERID=${TELEGRAM_USERID:-null}
WXSENDKEY=${WXSENDKEY:-null}
WXPUSH_URL=${WXPUSH_URL:-null}
WX_TOKEN=${WX_TOKEN:-null}
BUTTON_URL=${BUTTON_URL:-null}
LOGININFO=${LOGININFO:-N}

export TELEGRAM_TOKEN TELEGRAM_USERID BUTTON_URL

# 加密用户名的函数，保留前两位，其余用星号替换
encrypt_username() {
    local username="$1"
    local length=${#username}
    
    if [ $length -le 2 ]; then
        # 如果用户名长度小于等于2，全部显示
        echo "$username"
    else
        # 保留前两位，后面用星号填充
        local prefix="${username:0:2}"
        local stars=""
        for ((i=2; i<length; i++)); do
            stars="${stars}x"
        done
        echo "${prefix}${stars}"
    fi
}

# 使用 jq 提取 JSON 数组，并将其加载为 Bash 数组
hosts_info=($(echo "${HOSTS_JSON}" | jq -c ".info[]"))
summary=""

# 生成唯一的临时密钥文件标识
TEMP_KEY_PREFIX="temp_ssh_key_$(date +%s)"

for info in "${hosts_info[@]}"; do
  user=$(echo $info | jq -r ".username")
  host=$(echo $info | jq -r ".host")
  port=$(echo $info | jq -r ".port")
  pass=$(echo $info | jq -r ".password")
  
  # 加密用户名
  encrypted_user=$(encrypt_username "$user")

  echo "检查主机: $host, 用户: $encrypted_user, 端口: $port"
  
  # 创建临时密钥文件（用于密码认证）
  TEMP_KEY_FILE="${TEMP_KEY_PREFIX}_${host}_${port}"
  
  # 方法1：尝试使用密码通过SSH连接
  ssh_output=$(sshpass -p "$pass" ssh -o StrictHostKeyChecking=no \
                         -o ConnectTimeout=$SSH_TIMEOUT \
                         -o BatchMode=no \
                         -p $port \
                         $user@$host "$KEEPALIVE_CMD" 2>/dev/null)
  
  ssh_result=$?
  
  # 根据SSH返回状态判断连接结果
  if [ $ssh_result -eq 0 ]; then
    echo "SSH连接成功，账号正常"
    echo "服务器时间: $ssh_output"
    # 修改这里：将服务器时间明文显示在消息中
    msg="🟢主机 ${host}:${port}, 用户 ${encrypted_user}，SSH连接成功，账号正常！\n服务器时间: ${ssh_output}\n"
  elif [ $ssh_result -eq 5 ]; then
    echo "SSH连接被拒绝（可能是账户被封）"
    msg="🔴主机 ${host}:${port}, 用户 ${encrypted_user}，SSH连接被拒绝，账号可能被封！\n"
    chmod +x ./tgsend.sh
    export PASS=$pass
    ./tgsend.sh "CT8告警 - Host:${host}:${port}, user:${user}, SSH连接被拒绝，账号可能被封！"
  elif [ $ssh_result -eq 255 ]; then
    echo "SSH连接失败（网络或服务问题）"
    msg="🔴主机 ${host}:${port}, 用户 ${encrypted_user}，SSH连接失败，网络或服务问题！\n"
    chmod +x ./tgsend.sh
    export PASS=$pass
    ./tgsend.sh "CT8告警 - Host:${host}:${port}, user:${user}, SSH连接失败，请检查网络或服务状态"
  elif [ $ssh_result -eq 6 ]; then
    echo "用户名或密码错误"
    msg="🔴主机 ${host}:${port}, 用户 ${encrypted_user}，用户名或密码错误！\n"
    chmod +x ./tgsend.sh
    export PASS=$pass
    ./tgsend.sh "CT8告警 - Host:${host}:${port}, user:${user}, 用户名或密码错误！"
  else
    echo "SSH连接异常，返回码: $ssh_result"
    msg="🔴主机 ${host}:${port}, 用户 ${encrypted_user}，SSH连接异常，返回码: ${ssh_result}！\n"
    chmod +x ./tgsend.sh
    export PASS=$pass
    ./tgsend.sh "CT8告警 - Host:${host}:${port}, user:${user}, SSH连接异常，返回码: ${ssh_result}"
  fi
  
  summary=$summary$(echo -n $msg)
  
  # 清理临时文件（如果存在）
  rm -f "$TEMP_KEY_FILE" 2>/dev/null
done

if [[ "$LOGININFO" == "Y" ]]; then
  chmod +x ./tgsend.sh
  ./tgsend.sh "CT8 SSH保活报告：\n$summary"
fi

# 清理所有临时文件
rm -f ${TEMP_KEY_PREFIX}_* 2>/dev/null
