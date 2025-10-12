#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <libkern/OSCacheControl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>

static int g_log_fd = -1;
static void log_line(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    { va_list cp; va_copy(cp, ap); char buf[1024]; vsnprintf(buf, sizeof(buf), fmt, cp); va_end(cp); NSLog(@"[instantspaces] %s", buf); }
    if (g_log_fd == -1) {
        char path[PATH_MAX]; snprintf(path, sizeof(path), "/private/var/tmp/instantspaces.%d.log", getpid());
        g_log_fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    if (g_log_fd != -1) { char line[1024]; vsnprintf(line, sizeof(line), fmt, ap); write(g_log_fd, line, (unsigned)strlen(line)); write(g_log_fd, "\n", 1); fsync(g_log_fd); }
    va_end(ap);
}

static inline int hexval(char c){ if(c>='0'&&c<='9')return c-'0'; if(c>='a'&&c<='f')return 10+(c-'a'); if(c>='A'&&c<='F')return 10+(c-'A'); return -1; }
static size_t parse_pattern(const char *p,unsigned char *bytes,unsigned char *mask,size_t cap){
    size_t n=0; while(*p && n<cap){ while(*p==' ') p++; if(!*p) break;
        if(p[0]=='?'&&p[1]=='?'){ bytes[n]=0; mask[n]=0; n++; p+=2; }
        else { int hi=hexval(p[0]), lo=hexval(p[1]); if(hi<0||lo<0) break; bytes[n]=(unsigned char)((hi<<4)|lo); mask[n]=1; n++; p+=2; }
        if(*p==' ') p++;
    } return n;
}
static size_t search_buf(const unsigned char *buf,size_t buflen,const unsigned char *pat,const unsigned char *msk,size_t patlen,size_t start_off){
    if(!buf||patlen==0||buflen<patlen||start_off>buflen-patlen) return SIZE_MAX;
    size_t limit=buflen-patlen; for(size_t i=start_off;i<=limit;i++){ size_t j=0;
        for(;j<patlen;j++){ if(!msk[j]) continue; if(buf[i+j]!=pat[j]) break; }
        if(j==patlen) return i;
    } return SIZE_MAX;
}

static BOOL find_dock_text(uint64_t *out_text_start,uint64_t *out_text_size){
    uint32_t count=_dyld_image_count();
    for(uint32_t i=0;i<count;i++){
        const char *name=_dyld_get_image_name(i); if(!name) continue;
        if(!strstr(name,"/Dock.app/Contents/MacOS/Dock")) continue;
        const struct mach_header_64 *mh=(const struct mach_header_64*)_dyld_get_image_header(i);
        if(!mh||mh->magic!=MH_MAGIC_64) continue;
        intptr_t slide=_dyld_get_image_vmaddr_slide(i);
        const uint8_t *cur=(const uint8_t*)(mh+1);
        for(uint32_t c=0;c<mh->ncmds;c++){
            const struct load_command *lc=(const struct load_command*)cur;
            if(lc->cmd==LC_SEGMENT_64){
                const struct segment_command_64 *seg=(const struct segment_command_64*)cur;
                if(strcmp(seg->segname,"__TEXT")==0){
                    *out_text_start=seg->vmaddr + (uint64_t)slide;
                    *out_text_size =seg->vmsize;
                    return YES;
                }
            }
            cur += lc->cmdsize;
        }
    }
    return NO;
}

static void get_patterns(NSArray<NSString*> **out){
    NSOperatingSystemVersion v=[[NSProcessInfo processInfo] operatingSystemVersion];
    if(v.majorVersion==14){
        *out=@[
            @"00 10 6A 1E E0 03 14 AA ?? 03 ?? AA", // Sonoma
            @"00 10 6A 1E A8 ?? ?? D1 ?? 01 ?? F8"  // Sequoia fallback
        ];
    } else if(v.majorVersion==15){
        *out=@[
            @"00 10 6A 1E A8 ?? ?? D1 ?? 01 ?? F8", // Sequoia
            @"00 10 6A 1E E0 03 14 AA ?? 03 ?? AA"  // Sonoma fallback
        ];
    } else {
        *out=@[
            @"00 10 6A 1E E0 03 14 AA ?? 03 ?? AA",
            @"00 10 6A 1E A8 ?? ?? D1 ?? 01 ?? F8"
        ];
    }
}
static inline uint64_t page_align(uint64_t x){ return x & ~(uint64_t)(vm_page_size-1); }

// Record patched sites
static uint64_t g_patched_sites[64];
static int g_patched_count = 0;

static void record_patched(uint64_t addr){
    if(g_patched_count < (int)(sizeof(g_patched_sites)/sizeof(g_patched_sites[0]))){
        g_patched_sites[g_patched_count++] = addr;
    }
}

// Select patch opcode by env var: INSTANTSPACES_MODE = "zero" | "min0125"
static uint32_t pick_patch_insn(void){
    const char *mode = getenv("INSTANTSPACES_MODE");
    if (mode && strcmp(mode, "min0125") == 0) {
        // fmov d0, #0.125
        return 0x1e681000;
    }
    // default: zero duration (current behavior)
    // movi d0, #0 (as used by yabai Write)
    return 0x2f00e400;
}

static int patch_all_hits_in_text(uint64_t text_start,uint64_t text_size){
    NSArray<NSString*> *patterns=nil; get_patterns(&patterns);
    const uint32_t patchInsn = pick_patch_insn();
    int total_patched=0;

    for(NSString *ps in patterns){
        unsigned char pat[128], msk[128]; size_t plen=parse_pattern(ps.UTF8String, pat, msk, sizeof(pat));
        if(!plen) continue;
        size_t start_off=0;
        while(1){
            size_t off=search_buf((const unsigned char*)(uintptr_t)text_start,(size_t)text_size,pat,msk,plen,start_off);
            if(off==SIZE_MAX) break;
            uint64_t hit = text_start + off;
            uint32_t before = *(volatile uint32_t*)hit;

            kern_return_t kr = vm_protect(mach_task_self(), page_align(hit), vm_page_size, 0, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
            if(kr!=KERN_SUCCESS){ log_line("vm_protect RW failed @0x%llx: %d",(unsigned long long)hit,kr); return total_patched; }

            *(volatile uint32_t*)hit = patchInsn;
            sys_icache_invalidate((void*)(uintptr_t)hit, sizeof(uint32_t));
            __builtin___clear_cache((char*)(uintptr_t)hit,(char*)(uintptr_t)(hit+sizeof(uint32_t)));
            (void)vm_protect(mach_task_self(), page_align(hit), vm_page_size, 0, VM_PROT_READ|VM_PROT_EXECUTE);

            uint32_t after = *(volatile uint32_t*)hit;
            log_line("Patched site @0x%llx: before=0x%08x after=0x%08x pattern='%s'",
                     (unsigned long long)hit, before, after, ps.UTF8String);
            record_patched(hit);
            total_patched++;
            start_off = off + 1;
        }
    }
    return total_patched;
}

__attribute__((visibility("default"))) int instantspaces_patch(void){
#if !defined(__arm64__)
    return 1;
#else
    @autoreleasepool {
        const char *mode = getenv("INSTANTSPACES_MODE");
        log_line("instantspaces_patch: entered (mode=%s)", mode ? mode : "zero");
        uint64_t text_start=0, text_size=0;
        if(!find_dock_text(&text_start,&text_size)){ log_line("Failed to find Dock __TEXT; abort."); return 1; }
        log_line("Dock __TEXT=[0x%llx..0x%llx)",(unsigned long long)text_start,(unsigned long long)(text_start+text_size));
        g_patched_count = 0;
        int count = patch_all_hits_in_text(text_start,text_size);
        log_line("Total sites patched: %d", count);
        return count>0 ? 0 : 2;
    }
#endif
}

__attribute__((visibility("default"))) int instantspaces_verify(void){
#if !defined(__arm64__)
    return 1;
#else
    @autoreleasepool {
        log_line("Verify: patched_count=%d", g_patched_count);
        for(int i=0;i<g_patched_count;i++){
            uint64_t addr = g_patched_sites[i];
            uint32_t val = *(volatile uint32_t*)addr;
            log_line("Verify patched @0x%llx => 0x%08x", (unsigned long long)addr, val);
        }
        return g_patched_count;
    }
#endif
}

__attribute__((constructor)) static void ctor(void){
    log_line("constructor: payload loaded into Dock pid=%d", getpid());
    (void)instantspaces_patch();
}