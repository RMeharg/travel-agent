manifest=.tmp/concourse_deployment_manifest.yml
pre_merged_manifest=.tmp/pre_merged_manifest.yml

target(){
  TARGET=$1

  if [  -z "$TARGET" ]
  then
    echo "${red}You must provide a concourse target${reset}"
    echo ''
    echo 'USAGE: ./travel-agent target CONCOURSE_TARGET'
    exit 1
  fi

  fly -t travel-agent login -c $TARGET
}

# Clean old atifacts
clean(){
  rm -f manifest.go manifest 
}

clone_project(){
  project_path=$1
  echo $project_path
  if [ ! -z "$project_path" ] && [[ $1 == *".git" ]]  ; then
    project_dir=`basename $project_path .git`

    echo "Cloning $project_path ..."

    pushd /tmp > /dev/null
    rm -rf $project_dir
    git clone $project_path
    popd > /dev/null

    pushd /tmp/$project_dir > /dev/null
  else
    pushd $project_path > /dev/null
  fi
}

help() {
  cat << EOM

Travel agent helps you write concourse pipelines without repeating yourself.
TDD your pipeline templates and create jobs and resources for 1..N environments.

Running travel agent:

travel-agent SUBCOMMAND

Subcommands:

help
bootstrap   - Generates and upgrades travel agent project
target      - Sets concourse target. EG: https://1.2.3.4:9090
book  - compiles and dpeloys manifest.ego (manifest.ego) 
EOM
}

book() {
  echo 'Booking...'
  TRAVEL_AGENT_CONFIG=$1
  FILES_TO_MERGE=$*

  if [ -z "$TRAVEL_AGENT_CONFIG" ] ; then
    echo "${red}===> provide TAVEL_AGENT_CONFIG if you want to generate a manifest${reset}"
    exit 1
  fi

  if [ -z "$FILES_TO_MERGE" ] ; then
    echo "${red}===> provide FILES_TO_MERGE if you want to spruce merge secrets to manifest${reset}"
    exit 1
  fi

  if [ -n "$TRAVEL_AGENT_CONFIG" ] ; then
    TRAVEL_AGENT_PROJECT=$(cat "$1" | grep -v -e "^#" | grep -e "^git_project:" |  awk -F"git_project:" '{print $2}' )
    clone_project "$TRAVEL_AGENT_PROJECT"
  fi

  if ! [ -d "ci/manifest" ]; then
    echo "This does not look like a travel agent project"
    exit 1
  fi

  pushd ci/manifest > /dev/null

  clean

  ego -package main -o manifest.go

  printf "${green}===> Generating manifest for enviroments provided by the travel-agent.yml config file ...${reset}"
  NAME=$(grep -E "^name:" $TRAVEL_AGENT_CONFIG | awk -F " " '{print $2}')
  mkdir -p .tmp
  go run manifest.go main.go $TRAVEL_AGENT_CONFIG > $pre_merged_manifest
  echo "${green}done${reset}"

  printf "${green}===> Merging secrets from spruce-secret.yml into the generated manifest ...${reset}"
  spruce merge --prune meta $pre_merged_manifest $FILES_TO_MERGE > $manifest
  echo "${green}done${reset}"

  spruce merge $manifest > /dev/null

  fly -t travel-agent set-pipeline -c $manifest -p $NAME

  popd > /dev/null
}