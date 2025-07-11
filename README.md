# 3-tier-architecture-aws

VPC with 1 EC2 instance and RDS database, provisioned via Terraform.

## Services
- **1 EC2 Instance**: Public subnet (HTTPS/HTTP access)
- **1 RDS Instance**: Private subnet (MySQL/PostgreSQL)
- **VPC**: With 6 subnets and NACLs

```mermaid
flowchart TD
    Internet -->|HTTP/HTTPS| EC2
    EC2 -->|Database| RDS

    subgraph AWS_VPC[VPC]

subgraph PublicSubnet[Public Subnet]
            EC2[EC2 Instance\nAmazon Linux 2\nt3.micro]
        end
        subgraph PrivateSubnet[Private Subnet]
            RDS[(RDS MySQL\nPrivate Access Only)]
        end
    end
```
