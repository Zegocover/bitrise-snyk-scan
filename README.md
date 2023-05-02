# bitrise-snyk-scan
Build step for integrating snyk to bitrise pipeline. It can run both on MacOS and Linux hosts. This step scans any project, either it's single or monorepo for code and dependency scanning.

Dependencies managers supported:
- Cocoapods
- Gradle
- Yarn
- Npm

The step's workflow is as follows:
1. Fetch configuration
2. Download and authenticate to Snyk
3. Run Snyk SAST scan
4. Run Dependency scan
5. Fail step if any of the scan has findings or a failure occur (not blocking the build)

## How to use this Step in your pipeline

Create a workflow in your project's `bitrise.yml` as shown next

```
  workflow-snyk:
    steps:
    - git::https://github.com/Zegocover/bitrise-snyk-scan.git: 
        title: Snyk
        inputs:
        - project_directory: $BITRISE_SOURCE_DIR // project directory is different from the source dir?
        - os_list: ios // is the project ios or android?
        - severity_threshold: low // critical is not supported by'snyk code'
        - org_name: some_name // Used to configure snyk organisation setting
        - js_scan: false // Optional (set to true whenever needed) 
```

Then use this workflow as part of all other workflows you want to snyk scan e.g.

```
build-workflow:
    before_run:
    - workflow-clone
    - ... // any other step before snyk scan
    - workflow-snyk
    - ... // any other step after snyk scan
```

For testing you can create a separate workflow which will clone the project's repo and then run the snyk step. Tie it as per usual to your test branch with a trigger. Once tested, use it in production pipelines.

Do not forget to set your SNYK_AUTH_TOKEN in the secrets of the project.


## How to use this Step locally

Can be run directly with the [bitrise CLI](https://github.com/bitrise-io/bitrise),
just `git clone` this repository, `cd` into it's folder in your Terminal/Command Line
and call `bitrise run test`.

*Check the `bitrise.yml` file for required inputs which have to be
added to your `.bitrise.secrets.yml` file!*

Step by step:

1. Open up your Terminal / Command Line
2. `git clone` the repository
3. `cd` into the directory of the step (the one you just `git clone`d)
5. Create a `.bitrise.secrets.yml` file in the same directory of `bitrise.yml`
   (the `.bitrise.secrets.yml` is a git ignored file, you can store your secrets in it)
6. Check the `bitrise.yml` file for any secret you should set in `.bitrise.secrets.yml`
  * Best practice is to mark these options with something like `# define these in your .bitrise.secrets.yml`, in the `app:envs` section.
7. Once you have all the required secret parameters in your `.bitrise.secrets.yml` you can just run this step with the [bitrise CLI](https://github.com/bitrise-io/bitrise): `bitrise run test`

An example `.bitrise.secrets.yml` file:

```
envs:
- SNYK_AUTH_TOKEN: your authentication token
```

# Future additions
Swift package manager is going to be added when support will be released from Snyk.

# Further dependency managers support

Here is an example of Maven support that has not been tested or integrated in the code of this plugin. If you need it, copy, test and debug any issues and open a PR to this step.

```
    # check if pom.xml exists
    maven_file=$(find ${CODEFOLDER} -name 'pom.xml')

    if [ -n "${maven_file}" ]
    then
        echo "Install maven and dependencies"
        {
            curl https://dlcdn.apache.org/maven/maven-3/3.8.6/binaries/apache-maven-3.8.6-bin.tar.gz
            mv apache-maven-3.8.4-bin.tar.gz apache-maven.tar.gz
            tar -xvf apache-maven-3.8.4-bin.tar.gz -C /usr/local/apache-maven
            export MAVEN_HOME=/usr/local/apache-maven/apache-maven
            export PATH=$MAVEN_HOME/bin 

            pom_path = $(echo ${maven_file}%/*)
            cd ${pom_path}
            mvn dependency:copy-dependencies
        } || {
            echo "!!! Unable to install maven"
        }

        echo "--- Running Android dependency scan"
        ./snyk test --all-sub-projects --severity-threshold=${SEVERITY_THRESHOLD} 
    else
        echo "!!! No maven requirement file was found"
    fi
```

