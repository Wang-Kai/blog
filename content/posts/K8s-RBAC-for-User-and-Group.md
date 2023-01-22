---
title: "K8s RBAC 体系中的 User 和 Group"
date: 2023-01-22T19:44:22+08:00
draft: false
---

K8s RBAC 体系中，可以作为授权对象的有 3 个类型：User、Group、ServiceAccount。

`ServiceAccout` 作为 K8s 的一种资源类型，有具体的 API 可以操作，本文主要介绍没有具体资源定义，又相对查看困难的 User 、Group 两个对象。

## 如何创建 User 和 Group？

### 1. 签发 X509 Client 证书

通过 CA 签发证书，apiserver auth 逻辑会解析证书的 subject 对象，把其中 `common_name（CN）` 作为 User，`organization （O）` 作为 Group。例如：kubeconfig 所使用证书的内容（通过 [cfssl-certinfo](https://github.com/cloudflare/cfssl/releases) -cert admin.pem 查看）

```json
{
  "subject": {
    "common_name": "kubernetes-admin",
    "organization": "system:masters",
    "names": [
      "system:masters",
      "kubernetes-admin"
    ]
  },
  ...
}
```

在这个例子中，User 就是 kubernetes-admin，Group 是 system:masters，其他字段暂可忽略。


### 2. 向 kube-apiserver 提供静态文件

kube-apiserver 有一个 `--token-auth-file` 参数，通过该参数可以指向一个 csv 格式的文件，在文件内声明 user 和 group。这种方式**所声明的 user 和 group 长期有效，如果要变更文件内容的话，需要重新启动 apiserver**。

csv 文件默认为 4 列，分别是 token, user name, user uid，最后一列是 group 可选择性填写，多个 group 可以用 `,` 分隔。示例如下：

```csv
token,user,uid,"group1,group2,group3"
```

## 权限体系如何针对 User 和 Group 做权限校验？

和 ServiceAccount 一样，User 和 Group 的权限校验通过 K8s RBAC 机制，可以使用 RoleBinding 或 ClusterRoleBinding 来为 User 和 Group 做授权。

通过查看 RoleBinding 或者 ClusterRoleBinding 的 `subjects.kind` 描述可以看到 kind 有三个选项 "User"、"Group" 和 "ServiceAccount"，在这个字段指定需要授权的类型即可。

> KIND:     RoleBinding
> VERSION:  rbac.authorization.k8s.io/v1
>
> FIELD:    kind <string>
>
> DESCRIPTION:
>     Kind of object being referenced. Values defined by this API group are
>     "User", "Group", and "ServiceAccount". If the Authorizer does not
>     recognized the kind value, the Authorizer should report an error.

以 cluster-admin 的授权为例，如下 YAML 文件为 system:masters Group 授予 cluster-admin 角色（该角色拥有集群所有权限）。前面我们看到证书中 `organization` 签的就是 system:masters，所以这也就是为何通过该证书可以拥有 K8s admin 级别权限的原因。

为 Group system:masters 绑定 ClusterRole cluster-admin 权限。

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:masters
```

ClusterRole cluster-admin 拥有 K8s 所有资源的所有权限。

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: cluster-admin
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
- nonResourceURLs:
  - '*'
  verbs:
  - '*'
```

## 参考文档

- [Authenticating](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)