FROM openjdk:8-jdk-stretch

RUN apt-get update && apt-get upgrade -y && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000
ARG http_port=8080
ARG agent_port=50000
ARG JENKINS_HOME=/var/jenkins_home

ENV JENKINS_HOME $JENKINS_HOME
ENV JENKINS_SLAVE_AGENT_PORT ${agent_port}

# Skip setup wizard
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN mkdir -p $JENKINS_HOME \
  && chown ${uid}:${gid} $JENKINS_HOME \
  && groupadd -g ${gid} ${group} \
  && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history
# can be persisted and survive image upgrades
VOLUME $JENKINS_HOME

# `/usr/share/jenkins/ref/` contains all reference configuration we want
# to set on a fresh new installation. Use it to bundle additional plugins
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d
COPY security.groovy /usr/share/jenkins/ref/init.groovy.d/security.groovy

# Use tini as subreaper in Docker container to adopt zombie processes
ARG TINI_VERSION=v0.16.1
COPY tini_pub.gpg ${JENKINS_HOME}/tini_pub.gpg
RUN curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture) -o /sbin/tini \
  && curl -fsSL https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-static-$(dpkg --print-architecture).asc -o /sbin/tini.asc \
  && gpg --no-tty --import ${JENKINS_HOME}/tini_pub.gpg \
  && gpg --verify /sbin/tini.asc \
  && rm -rf /sbin/tini.asc /root/.gnupg \
  && chmod +x /sbin/tini

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION

# ENV JENKINS_VERSION ${JENKINS_VERSION:-2.121.1}
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.164.1}

# jenkins.war checksum, download will be validated using it
# ARG JENKINS_SHA=5bb075b81a3929ceada4e960049e37df5f15a1e3cfc9dc24d749858e70b48919
ARG JENKINS_SHA=65543f5632ee54344f3351b34b305702df12393b3196a95c3771ddb3819b220b

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha256sum -c -

ENV JENKINS_UC https://updates.jenkins.io
ENV JENKINS_UC_EXPERIMENTAL=https://updates.jenkins.io/experimental
ENV JENKINS_INCREMENTALS_REPO_MIRROR=https://repo.jenkins-ci.org/incrementals
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE ${http_port}

# will be used by attached slave agents:
EXPOSE ${agent_port}

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER root
RUN apt-get install -y wget

# Download Maven 3.6.1
RUN wget --no-verbose -O /tmp/apache-maven-3.6.1-bin.tar.gz http://apache.cs.utah.edu/maven/maven-3/3.6.1/binaries/apache-maven-3.6.1-bin.tar.gz

# Install Maven
RUN tar xzf /tmp/apache-maven-3.6.1-bin.tar.gz -C /opt/
RUN ln -s /opt/apache-maven-3.6.1 /opt/maven
RUN ln -s /opt/maven/bin/mvn /usr/local/bin
RUN rm -f /tmp/apache-maven-3.6.1-bin.tar.gz
ENV MAVEN_HOME /opt/maven
RUN chown -R jenkins:jenkins /opt/maven

# Download Sonar Scanner
RUN wget --no-verbose -O /tmp/sonar-scanner-cli-3.3.0.1492-linux.zip https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-3.3.0.1492-linux.zip

# Install Sonar Scanner
RUN unzip /tmp/sonar-scanner-cli-3.3.0.1492-linux.zip -d /opt/
RUN ln -s /opt/sonar-scanner-3.3.0.1492-linux /opt/sonar-scanner
RUN ln -s /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin
RUN rm -f /tmp/sonar-scanner-cli-3.3.0.1492-linux.zip
RUN chown -R jenkins:jenkins /opt/sonar-scanner

# Remove download archive files
RUN apt-get clean

USER ${user}

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
COPY tini-shim.sh /bin/tini
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
COPY install-plugins.sh /usr/local/bin/install-plugins.sh

RUN xargs /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

# Add pre-configure jenkins user, roles and folders
COPY config.xml ${JENKINS_HOME}/
COPY users/devopsadmin_5363875188139681679 ${JENKINS_HOME}/users/
COPY users/users.xml ${JENKINS_HOME}/users/
COPY users/usergroup1a_8797605135613461888 ${JENKINS_HOME}/users/
COPY users/usergroup1b_995718742155678125 ${JENKINS_HOME}/users/
COPY users/usergroup2a_6775891199370930611 ${JENKINS_HOME}/users/
COPY users/usergroup2b_8197134849313077716 ${JENKINS_HOME}/users/
COPY users/usergroup3a_20477496831509518 ${JENKINS_HOME}/users/
COPY users/usergroup3b_1811229520844806677 ${JENKINS_HOME}/users/
COPY users/usergroup4a_2579800591356723534 ${JENKINS_HOME}/users/
COPY users/usergroup4b_7631031392398340817 ${JENKINS_HOME}/users/
COPY users/usergroup5a_6181960236795692129 ${JENKINS_HOME}/users/
COPY users/usergroup5b_4437288476909917641 ${JENKINS_HOME}/users/
COPY users/usergroup6a_3214710707687548879 ${JENKINS_HOME}/users/
COPY users/usergroup6b_6182137220852700818 ${JENKINS_HOME}/users/
COPY jobs ${JENKINS_HOME}/