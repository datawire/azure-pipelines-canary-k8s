#!/bin/sh

# the URL we will stress
STRESS_URL="$1"

# minimum success rate for the stress test
MIN_SUCCESS_RATE=$2

# stress rate and duration
STRESS_RATE=${STRESS_RATE:-100}
STRESS_DURATION=${STRESS_DURATION:-30s}

# a temporary file for saving the results
RESULTS_LOG=/tmp/results.log

#########################################################################################

if [ -z "$STRESS_URL" ] ; then
    echo ">>> FATAL: no URL provided"
    exit 1
fi

if [ -z "$MIN_SUCCESS_RATE" ] ; then
    echo ">>> FATAL: no minimum success rate provided"
    exit 1
fi

command -v kubectl >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    echo ">>> kubectl does not seem to be installed: installing..."
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl

    echo ">>> Copying kubectl to /usr/local/bin"
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
    export PATH=/usr/local/bin:$PATH
fi

# maybe we need "az aks get-credentials"
# az aks get-credentials
# if [ $? -ne 0 ] ; then
#     echo ">>> FATAL: could not get credentials"
#     exit 1
# fi

echo ">>> Checking we can use kubectl..."
kubectl cluster-info
if [ $? -ne 0 ] ; then
    echo ">>> FATAL: kubectl does not seem to work"
    exit 1
fi

echo ">>> Looking for a Vegeta pod..."
vegeta_pod=$(kubectl get pods -l app=vegeta -o name 2>/dev/null | head -n1)
if [ -z "$vegeta_pod" ] ; then
    echo ">>> FATAL: no Vegeta pod detected."
    exit 1
fi
echo ">>> ... will run stress tests from $vegeta_pod"

vegeta_command="echo 'GET $STRESS_URL' | vegeta attack -insecure -rate=$STRESS_RATE -duration=$STRESS_DURATION | tee results.bin | vegeta report"

echo ">>> Stressing $STRESS_URL at $STRESS_RATE for $STRESS_DURATION..."
kubectl exec -ti $vegeta_pod -- sh -c "$vegeta_command" | tee $RESULTS_LOG
echo ">>> Stress test finished."

SUCCESS_RATE=$(cat $RESULTS_LOG | grep Success | grep ratio | rev | cut -d" " -f1 | rev | tr -d "%" | cut -f1 -d".")
echo ">>> $SUCCESS_RATE % success rate."

if [ $SUCCESS_RATE -lt $MIN_SUCCESS_RATE ] ; then
    echo ">>> Success rate $SUCCESS_RATE below threshold $MIN_SUCCESS_RATE: stress test failed."
    exit 1
fi

echo ">>> Stress test successful."
exit 0
