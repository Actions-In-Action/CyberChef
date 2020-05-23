#! /bin/bash

source "./assert.sh/assert.sh"

# check env
assert_not_empty "${SECRETS_PUSH_URL}"              "PUSH_URL"
assert_not_empty "${SECRETS_GITEE_USERNAME}"        "GITEE_USERNAME"
assert_not_empty "${SECRETS_GITEE_CLIENT_ID}"       "GITEE_CLIENT_ID"
assert_not_empty "${SECRETS_GITEE_CLIENT_SECRET}"   "GITEE_CLIENT_SECRET"
assert_not_empty "${SECRETS_GITEE_PASSWORD}"        "GITEE_PASSWORD"


echo "fetching the latest tag of gchq/CyberChef"
github_latest_tag=$(curl --silent "https://api.github.com/repos/gchq/CyberChef/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "${github_latest_tag}" ]; then
    echo "fetch the latest tag of gchq/CyberChef failed"

    exit 1
fi
echo "the latest tag of gchq/CyberChef is ${github_latest_tag}"


echo "checking remote CyberChef_${github_latest_tag}.zip file"
status_code=$(curl --write-out "%{http_code}\n" --silent --output /dev/null -I "https://gchq.github.io/CyberChef/CyberChef_${github_latest_tag}.zip")
if [ "${status_code}" != "200" ]; then
    echo "remote CyberChef_${github_latest_tag}.zip is not released"

    exit 1
fi
echo "remote CyberChef_${github_latest_tag}.zip is released"


echo "checking gitee tag"
if ! gitee_tag=$(curl --silent -X GET --header 'Content-Type: application/json;charset=UTF-8' "https://gitee.com/api/v5/repos/${SECRETS_GITEE_USERNAME}/CyberChef/tags"); then
    echo "checking gitee tag failed"

    exit 1    
fi

echo "gitee_tag: ${gitee_tag}"

if ! [[ "${gitee_tag}" =~ '"commit"' ]]; then
    echo "checking gitee tag failed"

    exit 1 
fi  

gitee_tag=$(echo "${gitee_tag}" | grep -oP "(?<=\")${github_latest_tag}(?=\")" | head -1)
echo "gitee_tag: ${gitee_tag}"

if [ "${gitee_tag}" = "${github_latest_tag}" ]; then
    echo "gitee tag ${gitee_tag} already synced"

    exit 0
fi
echo "begin to sync ${github_latest_tag}"


echo "cloning gitee repo"
git clone --depth 1 "https://gitee.com/${SECRETS_GITEE_USERNAME}/CyberChef.git"
if ! cd CyberChef; then
    echo "clone gitee repo failed"

    exit 1
fi


echo "downloading CyberChef_${github_latest_tag}.zip"
wget -q "https://gchq.github.io/CyberChef/CyberChef_${github_latest_tag}.zip"


echo "unzipping CyberChef_${github_latest_tag}.zip"
if ! unzip -o -q "CyberChef_${github_latest_tag}.zip"; then
    echo "unzip CyberChef_${github_latest_tag}.zip failed"

    exit 1
fi


rm CyberChef_*.zip*
mv "CyberChef_${github_latest_tag}.html" index.html


# log something to enable git push everytime...
echo "${github_latest_tag} $(date "+%Y-%m-%d %H:%M:%S")" >> mylog.log


git config --global http.postbuffer 524288000
git config user.name "${SECRETS_GITEE_USERNAME}"
git add .
git commit -m "${github_latest_tag}"


echo "git push to gitee"
if ! git push --repo "https://${SECRETS_GITEE_USERNAME}:${SECRETS_GITEE_PASSWORD}@gitee.com/${SECRETS_GITEE_USERNAME}/CyberChef.git"; then
    echo "git push to gitee failed"

    exit 1
fi


echo "wait 5 seconds after push"
sleep 5


echo "requesting gitee access token"
SECRETS_GITEE_ACCESS_TOKEN=$(curl --silent -X POST --data-urlencode "grant_type=password" --data-urlencode "username=${SECRETS_GITEE_USERNAME}" --data-urlencode "password=${SECRETS_GITEE_PASSWORD}" --data-urlencode "client_id=${SECRETS_GITEE_CLIENT_ID}" --data-urlencode "client_secret=${SECRETS_GITEE_CLIENT_SECRET}" --data-urlencode "scope=projects" https://gitee.com/oauth/token |  grep -oP '(?<="access_token":")[\da-f]+(?=")')
if [ "${SECRETS_GITEE_ACCESS_TOKEN}" = "" ]; then
    echo "request gitee access token failed"

    exit 1
fi


echo "rebuilding gitee pages"
rebuild_result=$(curl --silent -X POST --header 'Content-Type: application/json;charset=UTF-8' "https://gitee.com/api/v5/repos/${SECRETS_GITEE_USERNAME}/CyberChef/pages/builds" -d "{\"access_token\":\"${SECRETS_GITEE_ACCESS_TOKEN}\"}")
if [ "$(echo "${rebuild_result}"  | grep -oP "(?<=\")queued(?=\")")" != "queued" ]; then
    echo "rebuild gitee pages failed: ${rebuild_result}"

    exit 1         
fi


echo "git push new tag to gitee"
git tag -a "${github_latest_tag}" -m "${github_latest_tag}"
if ! git push --repo "https://${SECRETS_GITEE_USERNAME}:${SECRETS_GITEE_PASSWORD}@gitee.com/${SECRETS_GITEE_USERNAME}/CyberChef.git" --tags; then
    echo "git push new tag to gitee failed"
  
    exit 1
fi


# notify me
echo -e "$(date "+%Y-%m-%d %H:%M:%S")\n\
${GITHUB_REPOSITORY}\n\
${github_latest_tag} sync done." | curl --silent -X POST "${SECRETS_PUSH_URL}" --data-binary @- 
