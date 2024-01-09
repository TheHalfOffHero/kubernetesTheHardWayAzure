# 
#  Kubelet Client certificate for worker nodes
#  Requires that they be created prior to running

for instance in worker-0 worker-1; do
cat > ${instance}-csr.json <<EOF
{
  "CN": "system:node:${instance}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IT",
      "L": "Milan",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Italy"
    }
  ]
}
EOF

EXTERNAL_IP=$(az network public-ip show -g kubernetes \
  -n ${instance}-pip --query ipAddress -o tsv)

INTERNAL_IP=$(az vm show -d -n ${instance} -g kubernetes --query privateIps -o tsv)

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${instance},${EXTERNAL_IP},${INTERNAL_IP} \
  -profile=kubernetes \
  ${instance}-csr.json | cfssljson -bare ${instance}
done

