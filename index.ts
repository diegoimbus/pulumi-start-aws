import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";

// Hardcoded credentials for testing
const dbPassword = "testpassword123";

// Crear una VPC default y un security group que permita tráfico HTTP
const group = new aws.ec2.SecurityGroup("web-secgrp", {
  description: "Permitir trafico HTTP",
  ingress: [
    { protocol: "tcp", fromPort: 80, toPort: 80, cidrBlocks: ["0.0.0.0/0"] },
    { protocol: "tcp", fromPort: 3000, toPort: 3000, cidrBlocks: ["0.0.0.0/0"] }, // Frontend
    { protocol: "tcp", fromPort: 8000, toPort: 8000, cidrBlocks: ["0.0.0.0/0"] }, // API
    { protocol: "tcp", fromPort: 22, toPort: 22, cidrBlocks: ["0.0.0.0/0"] }, // SSH
  ],
  egress: [
    { protocol: "-1", fromPort: 0, toPort: 0, cidrBlocks: ["0.0.0.0/0"] },
  ],
});

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

// Instancia RDS PostgreSQL with hardcoded credentials
const db = new aws.rds.Instance("todo-db", {
  allocatedStorage: 20,
  engine: "postgres",
  engineVersion: "16.3",
  instanceClass: "db.t3.micro",
  dbName: "todo",
  username: "postgres",
  password: "testpassword123", // Hardcoded for testing
  skipFinalSnapshot: true,
  publiclyAccessible: true,
  dbSubnetGroupName: subnetGroup.name,
  vpcSecurityGroupIds: [dbSecurityGroup.id],
});

// Create the DATABASE_URL with hardcoded credentials for testing
const databaseUrl = pulumi.interpolate`postgresql://postgres:testpassword123@${db.endpoint}:5432/todo`;

const server = new aws.ec2.Instance("web-server", {
  instanceType: "t2.micro",
  ami: "ami-0731becbf832f281e", // Ubuntu en us-east-1
  userData: pulumi.interpolate`#!/bin/bash
sudo apt-get update
`,
  securityGroups: [group.name],
  tags: {
    Name: "Pulumi-WebServer",
  },
  keyName: "demo-ed25519",
});

// Exportar las URLs con los puertos actuales
export const frontendUrl = pulumi.interpolate`http://${server.publicIp}:3000`;
export const apiUrl = pulumi.interpolate`http://${server.publicIp}:8000`;
export const serverPublicIp = server.publicIp;
export const databaseEndpoint = db.endpoint;
export const sshCommand = pulumi.interpolate`ssh -i ~/.ssh/demo-ed25519 ubuntu@${server.publicIp}`;
