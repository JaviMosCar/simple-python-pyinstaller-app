# Entregable practicas. Fco Javier Moscoso Carrasco

## JenkinsFile

### Agent y Opciones Generales
El pipeline no utiliza un agente específico y tiene la opción de omitir etapas después de que se vuelva inestable.

pipeline {
    agent none 
    options {
        skipStagesAfterUnstable()
    }


### Etapa build
Esta etapa utiliza una imagen Docker de Python para compilar dos archivos fuente: add2vals.py y calc.py. Los resultados compilados se almacenan como un "stash" llamado compiled-results que incluye todos los archivos con extensión .py* en la carpeta sources.

    stages {
        stage('Build') { 
            agent {
                docker {
                    image 'python:3.12.1-alpine3.19' 
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py' 
                stash(name: 'compiled-results', includes: 'sources/*.py*') 
            }
        }

### Etapa test
Esta etapa utiliza una imagen Docker de Pytest para ejecutar pruebas. Las pruebas se ejecutan con el comando py.test y se genera un informe en formato JUnit llamado results.xml. Se garantiza que el informe JUnit se capture siempre.

        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }

### Etapa Deliver
En esta etapa, se utiliza cualquier agente disponible y se establecen variables de entorno. Se utiliza una imagen Docker específica (cdrx/pyinstaller-linux:python2) para generar un ejecutable a partir del archivo add2vals.py utilizando PyInstaller. Los resultados se almacenan como un artefacto y se realiza la limpieza de directorios build y dist después del éxito del pipeline.

        stage('Deliver') {
            agent any
            environment {
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) {
                    unstash(name: 'compiled-results')
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'"
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals"
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
}

## Terraform

### Configuración del Proveedor
terraform {
    required_providers {
        docker = {
            source = "kreuzwerker/docker"
            version = "3.0.1"
        }
    }
}

provider "docker" {
    host = "unix:///var/run/docker.sock"
}

### Creación de la Red Docker para Jenkins
resource "docker_network" "jenkins" {
    name = "jenkins"
    ipam_config {
        subnet = "172.21.0.0/24"
    }
}

### Imagen y Contenedor Docker para Docker en Docker
resource "docker_image" "dind" {
    name = "docker:dind"
    keep_locally = false
}

resource "docker_container" "jenkins_docker" {
    image = docker_image.dind.image_id
    name = "jenkins-docker"
    rm = true
    privileged = true
    
    networks_advanced {
        name = docker_network.jenkins.name
        ipv4_address = "172.21.0.2"
    }

    env = [
        "DOCKER_TLS_CERTDIR=/certs"
    ]

    ports {
        internal = 3000
        external = 3000
    }

    # Otras configuraciones de puertos y volúmenes...
}

### Imagen y Contenedor Docker para Jenkins Blue Ocean
resource "docker_image" "blueocean" {
    name = "myjenkins-blueocean:2.426.2-1"
    keep_locally = false
}

resource "docker_container" "jenkins_blueocean" {
    image = docker_image.blueocean.image_id
    name = "jenkins-blueocean"
    privileged = true
    depends_on = [docker_container.jenkins_docker]

    networks_advanced {
        name = docker_network.jenkins.name
    }

    # Configuración de variables de entorno, puertos y volúmenes...
}

### Volúmenes Docker para Jenkins
resource "docker_volume" "jenkins-docker-certs" {
    name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins-data" {
    name = "jenkins-data"
}

resource "docker_volume" "home-volume" {
    name = "home-volume"
}

## Dockerfile

Se utiliza la imagen base `jenkins/jenkins:2.426.1-jdk17`, que incluye Jenkins y Java Development Kit (JDK) 17.

FROM jenkins/jenkins:2.426.1-jdk17

Se cmabia a root

USER root

Se decargan paquetes

RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
  https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli

Se instalan en el usuario de jenkins

USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean:1.27.9 docker-workflow:572.v950f58993843"
