# VPC
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = "doc-processor-vpc"
    }
}

# Availability Zones

#get the list of AZs in current region
data "aws_availability_zones" "available" {
  state = "available"
}

#public subnets
resource "aws_subnet" "public_a" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.1.0/24"
    availability_zone = data.aws_availability_zones.available.names[0]
    map_public_ip_on_launch = true

    tags = {
        Name = "doc-processor-public-a"
        Tier = "public"
    }
}

resource "aws_subnet" "public_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.2.0/24"
    availability_zone = data.aws_availability_zones.available.names[1]
    map_public_ip_on_launch = true

    tags = {
        Name = "doc-processor-public-b"
        Tier = "public"
    }
}

#private subnets

resource "aws_subnet" "private_a"{
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.10.0/24"
    availability_zone = data.aws_availability_zones.available.names[0]

    tags = {
        Name = "doc-processor-private-a"
        Tier = "private"
    }
}

resource "aws_subnet" "private_b" {
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.11.0/24"
    availability_zone = data.aws_availability_zones.available.names[1]

    tags = {
        Name = "doc-processor-private-b"
        Tier = "private"
    }
}



#internet gateway

resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "doc-processor-igw"
    }
}


#NAT gateway

resource "aws_eip" "nat" {
    domain = "vpc"

    tags = {
        Name = "doc-processor-nat-eip"
    }

    depends_on = [aws_internet_gateway.main]
}

#single NAT Gateway in public sunet A (cost optimization)
resource "aws_nat_gateway" "main" {
    allocation_id = aws_eip.nat.id
    subnet_id = aws_subnet.public_a.id

    tags = {
        Name = "doc-processor-nat"
    }

    depends_on = [aws_internet_gateway.main]
}


#route tables

#public route table - routes internet traffic to the igw
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    route{
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = {
        Name = "doc-processor-public-rt"
    }
}

#Associate both public subnets with the public route table
resource "aws_route_table_association" "public_a" {
    subnet_id = aws_subnet.public_a.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
    subnet_id = aws_subnet.public_b.id
    route_table_id = aws_route_table.public.id
}

#private route table - routes internet traffic to the NAT Gateway
resource "aws_route_table" "private" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.main.id
    }

    tags = {
        Name = "doc-processor-private-rt"
    }

}

#Associate both private subnet with the private route table
resource "aws_route_table_association" "private_a" {
    subnet_id = aws_subnet.private_a.id
    route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
    subnet_id = aws_subnet.private_b.id
    route_table_id = aws_route_table.private.id
}


#outputs

output "vpc_id" {
    value = aws_vpc.main.id
}

output "public_subnets_ids" {
    value = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
    value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}