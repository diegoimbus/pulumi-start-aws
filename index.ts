import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";

const config = new pulumi.Config();
const dbPassword = config.requireSecret("dbPassword");

// Crear una VPC default y un security group que permita tráfico HTTP
const group = new aws.ec2.SecurityGroup("web-secgrp", {
  description: "Permitir trafico HTTP",
  ingress: [
    { protocol: "tcp", fromPort: 80, toPort: 80, cidrBlocks: ["0.0.0.0/0"] },
  ],
  egress: [
    { protocol: "-1", fromPort: 0, toPort: 0, cidrBlocks: ["0.0.0.0/0"] },
  ],
});

const server = new aws.ec2.Instance("web-server", {
  instanceType: "t2.micro",
  ami: "ami-0731becbf832f281e", // Ubuntu en us-east-1
  userData: pulumi.interpolate`#!/bin/bash
sudo apt-get update
sudo apt-get install -y docker.io git
sudo systemctl enable docker
sudo usermod -aG docker ubuntu

# Clonar el repo
cd /home/ubuntu
git clone https://github.com/Mark-kus/aws-todo.git app

# Entrar y levantar los contenedores
cd app
docker compose up -d
`,
  securityGroups: [group.name],
  tags: {
    Name: "Pulumi-WebServer",
  },
  keyName: "demo-ed25519",
});


// Exportar la IP pública
export const publicUrl = pulumi.interpolate`http://${server.publicIp}`;

// Subred default para RDS (usamos la VPC default para simplificar)
const subnetGroup = new aws.rds.SubnetGroup("db-subnet-group", {
  subnetIds: aws.ec2.getSubnets({}).then(subnets => subnets.ids),
  tags: {
    Name: "db-subnet-group",
  },
});

// Security Group para RDS que permita tráfico desde la EC2
const dbSecurityGroup = new aws.ec2.SecurityGroup("db-sg", {
  description: "Permitir acceso al RDS desde la EC2",
  ingress: [
    {
      protocol: "tcp",
      fromPort: 5432,
      toPort: 5432,
      securityGroups: [group.id], // permite tráfico desde EC2
    },
  ],
  egress: [
    { protocol: "-1", fromPort: 0, toPort: 0, cidrBlocks: ["0.0.0.0/0"] },
  ],
});

// Instancia RDS PostgreSQL
const db = new aws.rds.Instance("todo-db", {
  allocatedStorage: 20,
  engine: "postgres",
  engineVersion: "15.3",
  instanceClass: "db.t3.micro",
  name: "todo",
  username: "postgres",
  password: dbPassword,
  skipFinalSnapshot: true,
  publiclyAccessible: true,
  dbSubnetGroupName: subnetGroup.name,
  vpcSecurityGroupIds: [dbSecurityGroup.id],
});
