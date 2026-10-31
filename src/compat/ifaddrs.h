#ifndef SB_COMPAT_IFADDRS_H
#define SB_COMPAT_IFADDRS_H
struct ifaddrs {
  struct ifaddrs *ifa_next;
  char *ifa_name;
  unsigned int ifa_flags;
  struct sockaddr *ifa_addr, *ifa_netmask, *ifa_dstaddr;
  void *ifa_data;
};
extern int getifaddrs(struct ifaddrs **);
extern void freeifaddrs(struct ifaddrs *);
#endif
