#!/bin/bash
set -eou pipefail

function bashversion() {
    bash_version=$(bash --version | grep 1 | sed -nre 's/^[^0-9]*(([0-9]+\.)*[0-9]+).*/\1/p')
    v1=$(echo ${bash_version} | cut -d'.' -f1)
    v2=$(echo ${bash_version} | cut -d'.' -f2)

    new_bash=0
    if [ "$v1" -ge "4" ]; then
        new_bash=1
    elif [ "$v1" -eq "4" ] && [ "$v2" -gt "3" ]; then
        new_bash=1
    fi

    echo "$new_bash"
}

# for swift and objective-c
function snykscannerios-run() {
    export GEM_HOME=$HOME/.gem
    ruby_version="$(gem env | grep .gem/ruby | sed 's:.*.gem/::' | head -1)"
    export PATH=$GEM_HOME/${ruby_version}/bin:$PATH

    gem install cocoapods --user-install    
    pod install --project-directory=${project_directory} # for podfile

    bundle install # for gemfile

    echo "--- Running iOS dependency scan"
    ./snyk test --all-projects --severity-threshold=${severity_threshold}
}

# for java and kotlin
function snykscannerandroid-run() {
    echo "--- Install gradle"
    curl https://services.gradle.org/distributions/gradle-7.5.1-bin.zip --output gradle-7.5.1-bin.zip
    unzip -qq -d /opt/gradle gradle-7.5.1-bin.zip

    export PATH=$PATH:/opt/gradle/gradle-7.5.1/bin
    new_bash=$(bashversion)

    gradlew=()
    if [ "$new_bash" -eq "1" ]; then 
        gradlew="$(find ${CODEFOLDER} -name 'gradlew')"
        readarray -d ' ' gradlew < <(echo ${gradlew//"gradlew"/" "})
    else
        while IFS=  read -r -d $'\0'; do
            gradlew+=("$REPLY")
        done < <(find ${CODEFOLDER} -name 'gradlew' -print0)
    fi
    
    for i in "${gradlew[@]}"
    do
        dir=$(echo "$i" | sed 's|.*\\\(.*\)|\1|')
        cd $dir
        chmod +x ${dir}/gradlew
    done
    cd ${CODEFOLDER}

    scan_print="--- Running Android dependency scan"
    if [[ ${js_scan} == "true" ]]; then
        scan_print="--- Running Android and javascript dependency scan"
        snykscannerjs-run
    fi

    echo "--- Checking all build.gradle files in the project"
    gradle_files=()
    if [ "$new_bash" -eq "1" ]; then 
        gradle_files="$(find ${CODEFOLDER} -name 'build.gradle')"
        readarray -d ' ' gradle_files < <(echo ${gradle_files//"build.gradle"/" "})
    else
        while IFS=  read -r -d $'\0'; do
            gradle_files+=("$REPLY")
        done < <(find ${CODEFOLDER} -name 'build.gradle' -print0)
    fi

    len=${#gradle_files[@]};
    if [[ len -gt 0 ]]; then
        echo $scan_print
        ./snyk test --all-projects --severity-threshold=${severity_threshold}
    else
        echo '!!! No gradle requirement file was found'
    fi
}

function snykscannerjs-run() {
    echo "--- Downloading and installing project javascript dependencies."

    new_bash=$(bashversion)

    echo "--- Checking all yarn.lock files in the project"
    yarn_files=()
    if [ "$new_bash" -eq "1" ]; then 
        yarn_files="$(find ${CODEFOLDER} -name 'yarn.lock' -print0)"
        readarray -d ' ' yarn_files < <(echo ${yarn_files//"yarn.lock"/" "})
    else
        while IFS=  read -r -d $'\0'; do
            yarn_files+=("$REPLY")
        done < <(find ${CODEFOLDER} -name 'yarn.lock' -print0)
    fi

    len=${#yarn_files[@]};
    if [[ len -gt 0 ]]; then
        echo "--- Running yarn installation"
        for i in "${yarn_files[@]}"
        do
            dir=$(echo "$i" | sed 's|.*\\\(.*\)|\1|')
            cd $dir
            echo "Running yarn install for $dir"
            yarn install
        done
        cd ${CODEFOLDER}
    fi

    echo "--- Checking all package-lock.json files in the project"
    npm_files=()
    if [ "$new_bash" -eq "1" ]; then 
        npm_files="$(find ${CODEFOLDER} -name 'package-lock.json' -print0)"
        readarray -d ' ' npm_files < <(echo ${npm_files//"package-lock.json"/" "})
    else
        while IFS=  read -r -d $'\0'; do
            npm_files+=("$REPLY")
        done < <(find ${CODEFOLDER} -name 'package-lock.json' -print0)
    fi

    len=${#npm_files[@]};
    if [[ len -gt 0 ]]; then
        echo "--- Running npm installation"
        for i in "${npm_files[@]}"
        do
            dir=$(echo "$i" | sed 's|.*\\\(.*\)|\1|')
            cd $dir
            echo "Running npm install for $i"
            npm install
        done
        cd ${CODEFOLDER}
    fi
}



function main(){
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    CODEFOLDER=${BITRISE_SOURCE_DIR}

    if [[ -z "${os_list}" ]]
    then
        echo "os input is not valid"
        exit 1
    fi

    if [[ -z "${org_name}" ]]
    then
        echo "org_name input is not valid"
        exit 1
    fi

    echo "+++ Running Snyk Vulnerability Scanner Pipeline Step."

    echo "--- Identifying the application to scan."
    echo "Project path: ${CODEFOLDER}"

    echo "--- Downloading Snyk CLI"
    if [[ $OSTYPE == 'darwin'* ]]; then
        echo "OS: MacOS"
        curl https://static.snyk.io/cli/latest/snyk-macos -o snyk
    else
        echo "OS: Linux"
        curl https://static.snyk.io/cli/latest/snyk-linux -o snyk
    fi

    chmod +x ./snyk
    echo "--- Authenticating to Snyk."
    ./snyk auth ${snyk_auth_token} 
    ./snyk config set org=${org_name}

    # check if there are SAST findings
    sast_findings=false
    echo "--- Running code analysis scan" 
    {
        ./snyk code test --severity-threshold=${severity_threshold}
    } || {
        sast_findings=true
    }

    # check if there are dependency findings
    dep_findings=false
    {
        if [[ ${os_list} == "ios" ]]; then
            snykscannerios-run
        elif [[ ${os_list} == "android" ]]; then
            snykscannerandroid-run
        else
            echo "Unknown OS value"
            exit 1
        fi
    } || {
        dep_findings=true
    }

    if [ "$sast_findings" == "true" ] || [ "$dep_findings" == "true" ]; then
        exit 1
    else
        exit 0
    fi
}

main
