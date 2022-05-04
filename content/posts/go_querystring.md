---
title: "go-querystring：把结构体转为 URL query string 的利器"
date: 2022-05-03T11:31:43+08:00
draft: false
tags: [Go]
---

##  需求场景

后端服务在调用第三方 API 的时候，常见的需求就是构建 URL query string。在 go 标准包中有 [net/url](https://pkg.go.dev/net/url) 来解决这个问题，`url.Values` 的本质是一个 `map[string][]string`， 且提供一系列方法(Add、Del、Set)来操作参数，最终通过 `Encode()` 方法把 map 转为 URL query string。但其中会牵扯到一些重复性工作，比如：
1. 类型转换，要把 int、bool 等转为 string
2. 判断字段是否空或零值的处理逻辑

针对这个问题，google 开源的 [go-querystring](https://github.com/google/go-querystring)  可以优雅简洁的解决这类重复性工作。

## 使用介绍

整个 go-querystring 库对外仅暴露了一个方法 `func Values(v interface{}) (url.Values, error)`，该方法接收一个结构体，返回值是一个填充好数据的 `url.Values`。

默认的，URL query string 中 key 值是结构体字段名。如果字段不需要被编码，可以写上 `url:"-"` ，对于需要忽略空值的场景，要加上 `omitempty`，实例如下：

```go
type GetPodsReq struct {
	ClusterID int64  `form:"cluster_id" url:"cluster_id,omitempty"`
	Nodenames string `form:"nodenames" url:"nodenames,omitempty"`
	Selector  string `form:"selector" url:"selector,omitempty"`
	Hostnames string `form:"hostnames" url:"hostnames,omitempty"`
}
```
将结构体转为 query string 十分简单，仅需要一个  Values 方法调用即可把结构体转为 `url.Values`，然后通过 `url.Values` 的  Encode 方法构建出来 query string。

```go
v, err := query.Values(req)
if err != nil {
  return nil, err
}
url := fmt.Sprintf("%s/%s?%s", c.Domain, PathGetPods, v.Encode())
```

## 使用 go-querystring 改造老代码

在之前的工程代码中，我用了很多 if 判断来一个个加入 query 参数，有多少个参数，就要做多少次 if 判断。并且使用了 `net/url` 的一些其他方法，最终 encode 出 HTTP 请求的 URL。

```go
queryParams := url.Values{}
// 一个个判断参数，并且对于非 string 类型需要做转换
if req.ClusterID != 0 {
  queryParams.Add("cluster_id", fmt.Sprintf("%d", req.ClusterID))
}
if req.Selector != "" {
  queryParams.Add("selector", req.Selector)
}
if req.Nodenames != "" {
  queryParams.Add("nodenames", req.Nodenames)
}
if req.Hostnames != "" {
  queryParams.Add("hostnames", req.Hostnames)
}

// 构建 url 结构体
casterURL, err := url.Parse(fmt.Sprintf("%s/%s", c.Domain, PathGetPods))
if err != nil {
  return nil, err
}
casterURL.RawQuery = queryParams.Encode()

// 请求 URL
c.get(ctx, casterURL.String(), resp)
```

使用了 go-querystring 包后，代码就可以变得很简洁

```go
// 使用 query library 来填充结构体值到 url.Value
v, err := query.Values(req)
if err != nil {
  return nil, err
}
// 构造请求的 url string
url := fmt.Sprintf("%s/%s?%s", c.Domain, PathGetPods, v.Encode())
c.get(ctx, url, resp)
```

## 总结

go-querystring 是一个面向问题十分单一，手段又十分简洁的 library。简而言之，其就干了一件事情：**把自定义的结构体转为 url.Values**。面向问题十分专注，解决手段又十分极致，这也是每一个开源项目需要学习和借鉴的。

## 引用
- [go-querystring](https://github.com/google/go-querystring)
- [package godocs](https://pkg.go.dev/github.com/google/go-querystring/query#section-documentation)
