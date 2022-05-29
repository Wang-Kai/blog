---
title: "Linux free 命令的使用与理解"
date: 2022-05-29T12:03:32+08:00
draft: false
---

在使用 linux 操作系统时，常见的需求就是查看内存使用情况，比如分析系统健康状况，或者确定机器是否可以部署更多新的业务等等，这是一个常见的需求。

解决这个问题也很简单，多数云厂商提供的控制台都会展示各种机器指标的监控信息，内存使用率监控肯定是必不可少的。对 linux 了解一点的，也可以通过 free 命令来查看更详细的信息。当执行 free 命令的时候，不知道是否和我有同样的困惑：
- 打印的这么多列具体都代表什么意思？这些列之间的关系是怎样的？
- 内存可用率要看哪个指标？free 还是 available？



## 一、free 命令的基础使用
基础使用：free [options]

常用参数：
- `-h` human-readable 格式打印
- `-w` 把 cache & buffer 分开打印
- `-t` show total for RAM + swap

```shell
$ free -wth
              total        used        free      shared     buffers       cache   available
Mem:           125G        6.5G         87G        1.3G        3.5M         30G        116G
Swap:            0B          0B          0B
Total:         125G        6.5G         87G
```

## 二、free 命令各列的含义

free 命令打印的信息来自 `/proc/meminfo` （**/proc 不是一个存在于物理磁盘上的目录，而是用于提供内核信息的一个虚拟目录**），通过解析文件内容来展示物理内存、Swap 内存的使用情况。

| 指标  | 含义 |  /proc/meminfo 数据源    |
| :---- | ------- | ---- |
| total |  总计可用的物理内存，但不包含 kernel & OS 的内存占用  |  MemTotal    |
| free | 没有被使用的内存空间大小 | MemFree |
| buffers | linux 内核用来做缓存的空间大小 | Buffers |
| cache | 内存中用来做进程页缓存和 slabs 的空闲大小（slab 用作操作系统缓存） | Cached & SReclaimable |
| used | 通过其他参数计算出来的参数 | total - free - buffers - cache |
| shared | 用作 tmpfs 的内存空间 | Shmem |
| avaliable | 预估可用于启动一个新应用的内存空间 | MemAvailable |

## 三、可用内存要关注 free 列还是 avaliable？

**判断启动一个新进程还有多少内存空间可使用，需要关注 avaliable 数值。** avaliable 值通常要比 free 值要大，因为它加上了部分 cache & buffer 占用的空间。但又比 free + cache + buffers 要小，因为承认系统正常运行所需要的必要合理的缓存使用。

cache 的存在是由于 OS 运行中提升性能的需求。按照局部性原理，将未来可能用到的进程内存页做了缓存，减少了下次再需要该数据时产生缺页中断的概率。因为每发生一次缺页中断，就需要将进程置出，执行磁盘 I/O 读取数据，再将进程置为就绪态，是一个耗时操作。不做一些必要的 cache 就会导致磁盘 I/O 频繁、内存抖动，最终导致  CPU 使用率低。

avaliable 的统计并不是将所有的 cache & buffer 都统计在内，因为系统为了性能良好做一些缓存是合理的。从[源码](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=34e431b0a) 上看，系统计算可用内存时会将  `min(pagecache / 2, wmark_low)`  减掉，即在 1/2 cache 大小和最少要保存的空闲内存间选一个最小值，这部分值将不记作可用内存。所以这也就是为什么真正的 avaliable 值要比 free 值要大，而有比 free + cache + buffers 要小的原因了。

```c
for_each_zone(zone)
   wmark_low += zone->watermark[WMARK_LOW];

/*
* Estimate the amount of memory available for userspace allocations,
* without causing swapping.
*
* Free memory cannot be taken below the low watermark, before the
* system starts swapping.
*/
available = i.freeram - wmark_low;

/*
* Not all the page cache can be freed, otherwise the system will
* start swapping. Assume at least half of the page cache, or the
* low watermark worth of cache, needs to stay.
*/
pagecache = pages[LRU_ACTIVE_FILE] + pages[LRU_INACTIVE_FILE];
pagecache -= min(pagecache / 2, wmark_low);
available += pagecache;

/*
* Part of the reclaimable swap consists of items that are in use,
* and cannot be freed. Cap this estimate at the low watermark.
*/
available += global_page_state(NR_SLAB_RECLAIMABLE) -
        min(global_page_state(NR_SLAB_RECLAIMABLE) / 2, wmark_low);

if (available < 0)
   available = 0;
```

## 结论

`free` 是操作 linux 系统时一个常用命令，理解其各指标内在含义有一定门槛。操作系统的内存管理比较复杂，本质要解决的问题是**如何利用有限的内存空间最大化的存放更多的进程，同时减少缺页中断率**。


## 参考文档
- 《操作系统精髓与设计原理》第六版
- [provide estimated available memory](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=34e431b0a)
- [Anticipating Your Memory Needs](https://blogs.oracle.com/linux/post/anticipating-your-memory-needs)