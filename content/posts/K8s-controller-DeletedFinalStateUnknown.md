---
title: "K8s informer DeletedFinalStateUnknown 对象的来源与处理"
date: 2024-06-30T17:45:09+08:00
draft: false
---

之前生产环境 volcano 使用遇到一个问题，大致现象是：偶发出现一个 job 被删除了，但相关操作并未执行。最终通过 diff 旧版本与 volcano 最新版本，发现旧版本中未针对 `DeletedFinalStateUnknown` 场景做判断和处理，仿照新版本加上这段处理逻辑后问题修复。那么 `DeletedFinalStateUnknown` 对象是如何产生的？ controller 应该如何对其处理？作本文以记之。

## 来源：watch 断连丢失数据的补偿机制

在整个 controller 运行中，reflector 组件通过 ListWatch 机制直接与 apiserver 交互，将数据顺序写入 DetlaFIFO。

#### ListWatch 机制简介

[reflector](https://github.com/kubernetes/client-go/blob/master/tools/cache/reflector.go) 源码约 600 行，其中最主要的函数就是 ListAndWatch 和 watchHandler，这两个函数加起来足以阐述 ListWatch 机制。其大致分为两步：

1. 通过 List 方法从 apiserver 请求到全量的资源对象，并通过 Replace 方法将对象写入 DeltaFIFO 队列
2. 第一步中 List 同时拿到了最新的资源版本，然后调用 Watch 方法异步接收该版本之后的资源对象事件，根据事件类型调用不同方法将对象写入 DeltaFIFO 队列

除非遇到特别错误或收到停止信号，watch 过程中断连会重新执行 List 步骤，然后继续建立长连接 watch。但在重新 watch 的过程中就会遇到一个问题：**如果资源对象在中断过程中被删除了，那么如何让 controller 知道对象已被删除呢**？DeletedFinalStateUnknown 就是该问题的一个补偿方案。

Reflector 只负责与 apiserver 通信并将数据存入 DetlaFIFO 内，其中 List 得到的全量最新数据通过 Replace 方法写入，Watch 得到的数据通过 Add/Update/Delete 方法写入。可以说，List 执行结束后拿到的数据是那个时间点最新的数据，如果缓存中有数据不在其中，则表示数据已经被删除。

[DetlaFIFO](https://github.com/kubernetes/client-go/blob/master/tools/cache/delta_fifo.go) 会将缓存数据（队列内的数据或 indexer 数据，根据是否有 knownObjects 传入决定）与 Replace 方法传入的一组最新数据做对比，如果不在最新数据集合中，则向 DetlaFIFO 中插入 DeletedFinalStateUnknown（此时 Delta 事件类型为 Deleted），以表示该资源已被删除，但最终态未知。`DeletedFinalStateUnknown` 有两个字段 Key 和 Obj，如果确认数据已被删除，则 Obj 被赋值为 indexer 内 key 对应的数据，或 DetlaFIFO 内 key 对应的最新数据。

```go
type DeletedFinalStateUnknown struct {
        Key string
        Obj interface{}
}
```

## 处理：DeleteFunc 要做二次断言

在 controller 注册的资源处理函数中，DeleteFunc 如果针对指定资源类型断言失败，则需要再判断对象是否是 DeletedFinalStateUnknown 类型，以 K8s job-controller 为例：

```go
func (jm *Controller) deleteJob(logger klog.Logger, obj interface{}) {
        jm.enqueueSyncJobImmediately(logger, obj)
        jobObj, ok := obj.(*batch.Job)
        if !ok {
                tombstone, ok := obj.(cache.DeletedFinalStateUnknown)
                if !ok {
                        utilruntime.HandleError(fmt.Errorf("couldn't get object from tombstone %+v", obj))
                        return
                }
                jobObj, ok = tombstone.Obj.(*batch.Job)
                if !ok {
                        utilruntime.HandleError(fmt.Errorf("tombstone contained object that is not a job %+v", obj))
                        return
                }
        }
        jm.cleanupPodFinalizers(jobObj)
}
```

在这段代码中，controller 先判断 obj 是否为 Job 类型，如果不是则再次判断是否为 DeletedFinalStateUnknown 类型，然后对该 job 做处理。虽然最终 tombstone.Obj 不一定是最终态的 Job，但至少 controller 知道该对应已被删除，从而做相应的处理逻辑。





