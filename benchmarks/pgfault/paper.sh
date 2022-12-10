#
# Collecting data for Stew
#

DST_DIR=../../../faults-analysis/paper/micro
SRC_DIR=data/

# local, no reclaim, read
cp data/xput-fswap-noevict-local-read           ${DST_DIR}/xput-fastswap-noreclaim-local
cp data/xput-nohints-noevict-local-read         ${DST_DIR}/xput-eden-nohints-noreclaim-local
cp data/xput-hints-noevict-local-read           ${DST_DIR}/xput-eden-hints-noreclaim-local
                                                                                        
# rdma, no reclaim, read                                                                    
cp data/xput-fswap-noevict-rdma-read            ${DST_DIR}/xput-fastswap-noreclaim-rdma
cp data/xput-nohints-noevict-rdma-read          ${DST_DIR}/xput-eden-nohints-noreclaim-rdma
cp data/xput-hints-noevict-rdma-read            ${DST_DIR}/xput-eden-hints-noreclaim-rdma
                                                                                        
# rdma, reclaim, read                                                                   
cp data/xput-fswap-evict-rdma-read              ${DST_DIR}/xput-fastswap-reclaim-rdma
cp data/xput-hints-evict-rdma-read              ${DST_DIR}/xput-eden-hints-reclaim-rdma
cp data/xput-hints-evict8-rdma-read             ${DST_DIR}/xput-eden-hints-reclaim8-rdma
cp data/xput-hints-evict16-rdma-read            ${DST_DIR}/xput-eden-hints-reclaim16-rdma
                                                                                            
# rdma, reclaim, write                                                                   
cp data/xput-fswap-evict-rdma-write             ${DST_DIR}/xput-fastswap-reclaim-dirty-rdma
cp data/xput-hints-evict-rdma-write             ${DST_DIR}/xput-eden-hints-reclaim-dirty-rdma
cp data/xput-hints-evict8-rdma-write            ${DST_DIR}/xput-eden-hints-reclaim8-dirty-rdma
cp data/xput-hints-evict16-rdma-write           ${DST_DIR}/xput-eden-hints-reclaim16-dirty-rdma
                                                                                            
# local, rdahead, read                                                                   
cp data/xput-hints-noevict-local-read           ${DST_DIR}/xput-eden-hints-rdahead0-local
cp data/xput-hints+1-noevict-local-read         ${DST_DIR}/xput-eden-hints-rdahead1-local
cp data/xput-hints+2-noevict-local-read         ${DST_DIR}/xput-eden-hints-rdahead2-local
cp data/xput-hints+4-noevict-local-read         ${DST_DIR}/xput-eden-hints-rdahead4-local
                                                                                            
# rdma, rdahead, read                                                                   
cp data/xput-hints-noevict-rdma-read            ${DST_DIR}/xput-eden-hints-rdahead0-rdma
cp data/xput-hints+1-noevict-rdma-read          ${DST_DIR}/xput-eden-hints-rdahead1-rdma
cp data/xput-hints+2-noevict-rdma-read          ${DST_DIR}/xput-eden-hints-rdahead2-rdma
cp data/xput-hints+4-noevict-rdma-read          ${DST_DIR}/xput-eden-hints-rdahead4-rdma
