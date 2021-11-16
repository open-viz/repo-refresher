#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=openviz-repo-refresher # -$(date +%s)
COMMIT_MSG="Use dependencies"

REPO_ROOT=/tmp/openviz-repo-refresher

# KUBEDB_API_REF=${KUBEDB_API_REF:-1969d04c0945a0b9f69f18308912519588834481}

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 https://${GITHUB_USER}:${GITHUB_TOKEN}@$1.git
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    if [ -f go.mod ]; then
        # if [ "$1" != "github.com/kubedb/apimachinery" ]; then
        #     go mod edit \
        #         -require kubedb.dev/apimachinery@${KUBEDB_API_REF}
        #     go mod tidy
        # fi
        go mod edit \
            -require=kmodules.xyz/client-go@091bd089a92dd44e734ad5ccc3fef72fc8a1043b \
            -require=kmodules.xyz/monitoring-agent-api@ca48f83c44c5e0bfd46a580e73eeac18e2bd2d4b \
            -require=kmodules.xyz/webhook-runtime@ac7adedbd68016478ad656b8b751775142351be3 \
            -require=kmodules.xyz/resource-metadata@v0.6.7 \
            -require=kmodules.xyz/custom-resources@7ab2db03cce8470a57f13cdb89a1ee5b47f2df7d \
            -require=kmodules.xyz/objectstore-api@b9135743b78beee7af03b309c36ac18294943600 \
            -require=kmodules.xyz/offshoot-api@3e217667cf417e3fa8a935f422c9053f6feac830 \
            -require=go.bytebuilders.dev/license-verifier@v0.9.5 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.9.5 \
            -require=go.bytebuilders.dev/audit@v0.0.12 \
            -require=gomodules.xyz/x@v0.0.8 \
            -require=gomodules.xyz/logs@v0.0.6 \
            -replace=github.com/satori/go.uuid=github.com/gomodules/uuid@v4.0.0+incompatible \
            -replace=github.com/dgrijalva/jwt-go=github.com/gomodules/jwt@v3.2.2+incompatible \
            -replace=github.com/golang-jwt/jwt=github.com/golang-jwt/jwt@v3.2.2+incompatible \
            -replace=github.com/form3tech-oss/jwt-go=github.com/form3tech-oss/jwt-go@v3.2.5+incompatible \
            -replace=helm.sh/helm/v3=github.com/kubepack/helm/v3@v3.6.1-0.20210518225915-c3e0ce48dd1b \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.21.2-0.20210716212718-83e5493ac170
        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # run an extra make fmt because when make gen fails, make fmt is not run
        make fmt || true
    )
    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin $PR_BRANCH -f
        hub pull-request \
            --labels automerge \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1
