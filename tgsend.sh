#!/bin/bash

message_text=$1

replaceValue() {
  local url=$1
  local target=$2
  local value=$3
  local result
  result=$(printf '%s' "$url" | sed "s|#${target}|${value//&/\\&}|g")
  echo "$result"
}

toBase64() {
  echo -n "$1" | base64
}

urlencode() {
  local input="$1"
  local output=""
  local length=${#input}
  for ((i = 0; i < length; i++)); do
    local char="${input:i:1}"
    case "$char" in
    [a-zA-Z0-9.~_-]) output+="$char" ;;
    *) output+="$(printf '%%%02X' "'$char")" ;;
    esac
  done
  echo "$output"
}

toTGMsg() {
  local msg=$1
  local title="*ct8通知*"
  local host_icon="🖥️"
  local user_icon="👤"
  local time_icon="⏰"
  local notify_icon="📢"

  # 获取当前时间
  local current_time=$(date "+%Y-%m-%d %H:%M:%S")

  if [[ "$msg" != Host:* ]]; then
    local formatted_msg="${title}  \n\n"
    formatted_msg+="${time_icon} *时间：* ${current_time}  \n"
    formatted_msg+="${notify_icon} *通知内容：*    \n$msg  \n\n"
    echo -e "$formatted_msg"
    return
  fi

  local host=$(echo "$msg" | sed -n 's/.*Host:\([^,]*\).*/\1/p' | xargs)
  local user=$(echo "$msg" | sed -n 's/.*user:\([^,]*\).*/\1/p' | xargs)
  local notify_content=$(echo "$msg" | sed -E 's/.*user:[^,]*,//' | xargs)

  # 格式化消息内容，Markdown 换行使用两个空格 + 换行
  local formatted_msg="${title}  \n\n"
  formatted_msg+="${host_icon} *主机：* ${host}  \n"
  formatted_msg+="${user_icon} *用户：* ${user}  \n"
  formatted_msg+="${time_icon} *时间：* ${current_time}  \n\n"
  formatted_msg+="${notify_icon} *通知内容：* ${notify_content}  \n\n"

  echo -e "$formatted_msg|${host}|${user}" # 使用 -e 选项以确保换行符生效
}

telegramBotToken=${TELEGRAM_TOKEN}
telegramBotUserId=${TELEGRAM_USERID}
result=$(toTGMsg "$message_text")
formatted_msg=$(echo "$result" | awk -F'|' '{print $1}')
host=$(echo "$result" | awk -F'|' '{print $2}')
user=$(echo "$result" | awk -F'|' '{print $3}')

if [[ "$BUTTON_URL" == "null" ]]; then
  button_url="https://www.youtube.com/@frankiejun8965"
else
  button_url=${BUTTON_URL:-"https://www.youtube.com/@frankiejun8965"}
fi

URL="https://api.telegram.org/bot${telegramBotToken}/sendMessage"

if [[ -n "$host" ]]; then
  button_url=$(replaceValue $button_url HOST $host)
fi
if [[ -n "$user" ]]; then
  button_url=$(replaceValue $button_url USER $user)
fi
if [[ -n "$PASS" ]]; then
  pass=$(toBase64 $PASS)
  button_url=$(replaceValue $button_url PASS $pass)
fi
encoded_url=$(urlencode "$button_url")
#echo "encoded_url: $encoded_url"
reply_markup='{
    "inline_keyboard": [
      [
        {"text": "点击查看", "url": "'"${encoded_url}"'"}
      ]
    ]
  }'
#echo "reply_markup: $reply_markup"
#echo "telegramBotToken:$telegramBotToken,telegramBotUserId:$telegramBotUserId"
if [[ -z ${telegramBotToken} ]]; then
  echo "未配置TG推送"
else
  res=$(curl -s -X POST "https://api.telegram.org/bot${telegramBotToken}/sendMessage" \
    -d chat_id="${telegramBotUserId}" \
    -d parse_mode="Markdown" \
    -d text="$formatted_msg" \
    -d reply_markup="$reply_markup")
  if [ $? == 124 ]; then
    echo 'TG_api请求超时,请检查网络是否重启完成并是否能够访问TG'
    exit 1
  fi
  #echo "res:$res"
  resSuccess=$(echo "$res" | jq -r ".ok")
  if [[ $resSuccess = "true" ]]; then
    echo "TG推送成功"
  else
    echo "TG推送失败，请检查TG机器人token和ID"
  fi
fi
