// MARK: - 职责说明：三级图片加载管线（docs/03 §5.2）——内存 NSCache 60MB → 磁盘 LRU 200MB → PHCachingImageManager。
// 网格 / 浏览页禁止直接 requestImage（AGENTS.md §3.6）；同 id+size 在途请求合并；低内存清空内存层。
// TODO(P1): ImagePipelineProtocol（thumbnail/prefetch/cancel/fullImage(progress:)）+ MemoryCache + DiskCache。
