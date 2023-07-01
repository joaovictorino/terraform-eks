# Terraform criando Elastic Kubernetes Service na AWS

Pré-requisitos

- aws-cli instalado
- Terraform instalado

Logar no Azure via aws-cli, o navegador será aberto para que o login seja feito

```sh
aws configure sso
```

Inicializar o Terraform

```sh
terraform init
```

Executar o Terraform

```sh
terraform apply -auto-approve
```

Adicionar credenciais do EKS no kubectl local

```sh
aws eks --region us-east-1 update-kubeconfig --name eks_demo
```
