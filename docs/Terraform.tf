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

resource "docker_network" "jenkins" {
    name = "jenkins"
    ipam_config {
        subnet = "172.21.0.0/24"
    }
}

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
        "DOCKER_TLS_CERTDIR = /certs"
    ]

    ports {
        internal = 3000
        external = 3000
    }

    ports {
        internal = 5000
        external = 5000
    }

    ports {
        internal = 2376
        external = 2376
    }

    volumes {
        volume_name = docker_volume.jenkins-docker-certs.name
        container_path = "/certs/client"
    }

    volumes {
        volume_name = docker_volume.jenkins-data.name
        container_path = "/var/jenkins_home"
    }
}

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

    # Tenemos que indicar la ip del conetenedor dind
    env = [
        "DOCKER_HOST=tcp://172.21.0.2:2376",
        "DOCKER_CERT_PATH=/certs/client",
        "DOCKER_TLS_VERIFY=1",
        "JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true",
    ]

    ports {
        internal = 8080
        external = 8080
    }

    ports {
        internal = 50000
        external = 50000
    }

    volumes {
        volume_name = docker_volume.jenkins-docker-certs.name
        container_path = "/certs/client"
    }

    volumes {
        volume_name = docker_volume.jenkins-data.name
        container_path = "/var/jenkins_home"
    }

    volumes {
        volume_name = docker_volume.home-volume.name
        container_path = "/home"
    }
    restart = "on-failure"
}

resource "docker_volume" "jenkins-docker-certs" {
    name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins-data" {
    name = "jenkins-data"
}

resource "docker_volume" "home-volume" {
    name = "home-volume"
}
