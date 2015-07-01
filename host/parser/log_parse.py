import fileinput
import sys
import os
import re
import struct

### Packet Format ###
SIZE_PACKET_12 = 12
SIZE_PACKET_14 = 14
FMT_PACKET_12 = '>BIIHB' # '>' means big-endian
FMT_PACKET_14 = '>BIIIB' # '>' means big-endian
oWR, oRD, oER, oRS, oNONE = 0, 1, 2, 3, 9

oper = { 0:'WR',
         1:'RD',
         2:'ER',
         3:'RS' }

F_OPER        = 0
F_ADDR_BLOCK  = 1
F_ADDR_PAGE   = 2
F_BADBITS     = 3
F_LATENCY     = 4

BAD_BITS_THRESHOLD = 300
BAD_BLOCK_THRESHOLD = 100 #num pages (which didn't failed for WR) or (had less than BAD_BITS_THRESHOLD)

EXCLUDE_WR_FAILS = False#True


### Print Format ###
hdr_pr = '%s %3s %3s %8s %6s %s %s'
hdr_fo = '%s,%s,%s,%s,%s,%s,%s'
fmt_pr = '%s %3X %3X %8d %6d %1d %3d'
fmt_fo = '%s,%d,%d,%d,%d,%d,%d'

print_seq = ['name','avg','sum','cnt','min','max','distribution']
merged_seq = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','WR_LAT','WR_FAIL','RD_LAT','RD_BAD_BITS','ER_LAT','ER_FAIL']

class stat: # for unsigned numbers
    def __init__(self, name, distribution_max=65000, distribution_unit=100):
        self.name = name
        self.distribution_max = distribution_max
        self.distribution_unit = distribution_unit
        self.distribution_maxidx = self.distribution_max/self.distribution_unit
        self.distribution_data = [0] * ( self.distribution_maxidx + 1)
        self.init()

    def init(self):
        self.cnt = 0
        self.sum = 0
        self.stdev_sum = 0
        self.maxval = 0
        self.minval = 0x7FFFFFFFF

    def add(self, num):
        self.cnt += 1
        self.sum += num
        self.stdev_sum += (num*num)
        if(self.maxval < num ): self.maxval = num
        if(self.minval > num ): self.minval = num

        cur_distribution_idx = num/self.distribution_unit
        if cur_distribution_idx > self.distribution_maxidx: cur_distribution_idx = self.distribution_maxidx
        self.distribution_data[cur_distribution_idx] += 1

    def get_stat(self):
        distribution_output={}
        for i in range(0,self.distribution_maxidx):
            distribution_output[str(self.distribution_unit*i)+'~'+str(self.distribution_unit*(i+1))] = self.distribution_data[i]
        distribution_output[str(self.distribution_unit*self.distribution_maxidx)+'~'] = self.distribution_data[self.distribution_maxidx]

        return {'name':self.name, 'cnt':self.cnt, 'sum':self.sum, 'stdev':self.stdev_sum,\
                'min':self.minval, 'max':self.maxval, 'distribution':distribution_output}

    def write_file_header(self,file):
        # write data headers
        for x in print_seq:
            if(x == 'distribution'):
                break
            file.write( x )
            file.write( ',' )

        # write distribution list headers
        for i in range(0,self.distribution_maxidx):
            file.write( str(self.distribution_unit*i)+'~'+str(self.distribution_unit*(i+1)) )
            file.write( ',' )
        file.write( str(self.distribution_unit*self.distribution_maxidx)+'~' )

        file.write('\n')

    def write_file_stat(self,file):
        #write data
        for x in print_seq:
            if(x == 'distribution'):
                break
            elif(x == 'avg'):
                avg = 0
                if self.get_stat()['cnt']>0:
                    avg = self.get_stat()['sum'] / self.get_stat()['cnt']
                file.write( str(avg) + ',' )
                continue
            file.write( str(self.get_stat()[x]) )
            file.write( ',' )

        #write distribution list
        for i in range(0,self.distribution_maxidx):
            file.write( str(self.distribution_data[i]) )
            file.write( ',' )
        file.write( str(self.distribution_data[self.distribution_maxidx]) )

        file.write('\n')

    def getAvgStr(self):
        if self.get_stat()['cnt']>0:
            avg = str( float(self.get_stat()['sum']) / float(self.get_stat()['cnt']) )
        else:
            avg = ''
        return avg



def main():
    print('[INFO] Open FPGA NVM Log Parser')

    fx_name = 'summary.csv'
    fx      = open(fx_name, 'wb')

    for file in sorted(sys.argv[1:]):
        with open(file, 'rb') as fi: # Load result binary file
            fo_name = file+'.csv'
            fo = open(fo_name, 'wb') # Converted file

            fs_name = file+'_stat_ber.csv'
            fs = open(fs_name, 'wb') # Statistics file

            fsf_name = file+'_stat_ber_filtered.csv'
            fsf = open(fsf_name, 'wb') # Statistics file - filtered

            fl_name = file+'_stat_lat.csv'
            fl = open(fl_name, 'wb') # Statistics file - latency

            if(SIZE_PACKET_12 != struct.calcsize(FMT_PACKET_12)):
                print("Please Verify Packet Format")
                return
            if(SIZE_PACKET_14 != struct.calcsize(FMT_PACKET_14)):
                print("Please Verify Packet Format")
                return

            print('[INFO] INPUT  : %s'%file)
            print('[INFO] OUTPUT : %s'%fo_name)

            bin = fi.read()
            fi.close()
            
            '''
            fo.write( (hdr_fo+'\n')%('OP','BLK','PG','LAT_NS','BAD_BITS','PAGE_TYPE','SHARED_PAGE') )
            # print   ( hdr_pr    %('OP','BLK','PG','LAT_NS','PAGE_TYPE') )
            '''
            #determine/verify packet size
            offset = 0
            verify_size_hit = 0
            verify_size_miss = 0
            SIZE_PACKET = SIZE_PACKET_12 #start with 12
            FMT_PACKET  = FMT_PACKET_12

            while (len(bin)-offset) >= 10:
                data = struct.unpack(FMT_PACKET, bin[offset+0:offset+SIZE_PACKET])
                offset += SIZE_PACKET

                if (data[4] == 0xEE): verify_size_hit += 1
                else: verify_size_miss += 1

                if (verify_size_miss == 0 and verify_size_hit>=5):
                    print( 'PACKET_SIZE = %d'%(SIZE_PACKET) )
                    break
                elif (verify_size_miss > 0 and SIZE_PACKET == SIZE_PACKET_12):
                    SIZE_PACKET = SIZE_PACKET_14
                    FMT_PACKET  = FMT_PACKET_14
                    offset = 0
                    verify_size_miss = 0
                    verify_size_hit  = 0

            if verify_size_miss>0:
                print('[ERROR] Can not find packet pattern!')
                return

            offset=0

            # latency stat init
            last_oper_type_i = oNONE
            all_lats = [ [stat('all_'+oper[0]+'_p0',7500000,60000),\
                          stat('all_'+oper[0]+'_p1',7500000,60000),\
                          stat('all_'+oper[0]+'_p2',7500000,60000)],

                         [stat('all_'+oper[1]+'_p0',7500000,60000),\
                          stat('all_'+oper[1]+'_p1',7500000,60000),\
                          stat('all_'+oper[1]+'_p2',7500000,60000)],

                         [stat('all_'+oper[2],7500000,60000)] ]
            all_lat = stat('all',7500000,60000)
            block_lats = []
            block_lat = stat('block_all_0',7500000,60000)
            block_lat.write_file_header(fl)

            # BER stat init
            last_block = -1
            all_stat = stat('all')
            all_filtered_stat = stat('all_filtered',BAD_BITS_THRESHOLD,BAD_BITS_THRESHOLD/10)
            block_stat = stat('block0')
            block_filtered_stat = stat('block_filtered_0',BAD_BITS_THRESHOLD,BAD_BITS_THRESHOLD/10)
            all_stat.write_file_header(fs)
            all_filtered_stat.write_file_header(fsf)
            bad_blocks = []
            good_blocks = []

            merged_data={}
            # mram_iter = -1
            # mram_bad_bits_sum = 0
            while (len(bin)-offset) >= 10:
                data = struct.unpack(FMT_PACKET, bin[offset+0:offset+SIZE_PACKET]) # '>' means big-endian
                offset += SIZE_PACKET

                oper_type_i= data[0]
                oper_type  = oper[oper_type_i]
                addr_block = (data[1]>>9)&0xFFF    #32bit = 11dummy + 12block + 9page
                addr_page  = data[1]&0x1FF
                latency_ns = data[2]*10
                bad_bits   = data[3]
                fail_info_W= data[3]&(data[3]>>5)           #[7:0]={WP,RDY,ARDY,RSVD4,RSVD3,RSVD2,FAILC,FAIL}
                fail_info_E= (fail_info_W&0x01)

                if(addr_page<=5):   page_type = ( 0 )
                elif(addr_page<=7): page_type = ( 1 )
                else:               page_type = ( ((addr_page-8)/2)%3 )

                if(addr_page<=5):   addr_shared_page = ( addr_page )
                elif(addr_page<=7): addr_shared_page = ( addr_page-4 )
                else:
                    tmpidx = addr_page - ( 8 * (page_type+1) )
                    addr_shared_page = ( 6 + (tmpidx/3) + (tmpidx%3) )

#                #mram temp
#                if oper_type_i == oRD:
#                    mram_bad_bits_sum += bad_bits
#                    # print "%s %6X %6X %8X %4X"%(oper[oper_type_i], addr_block, addr_page, latency_ns/10, bad_bits)
#                if oper_type_i == oWR:
#                    if int(mram_iter) != int(latency_ns/10):
#                        if mram_iter != -1:
#                            print "%10d, %10d"%(mram_iter, mram_bad_bits_sum)
#                        mram_bad_bits_sum = 0
#                        mram_iter = int(latency_ns/10)
#                continue

                # Merged_data process
                if not ( (addr_block, addr_page) in merged_data ):
                    merged_data.update({ (addr_block, addr_page) : {} })
                    merged_data[(addr_block, addr_page)].update(
                    { 'PAGE_TYPE': page_type,
                      'PAGE_GROUP':addr_shared_page,
                    })

                if oper_type_i == oWR:
                    merged_data[(addr_block, addr_page)].update(
                    {
                        'WR_LAT': latency_ns,
                        'WR_FAIL': fail_info_W,
                    })
                    if EXCLUDE_WR_FAILS and fail_info_W != 0:
                        merged_data[(addr_block, addr_page)].update(
                        {
                            'WR_LAT': -latency_ns,
                        })
                elif oper_type_i == oRD:
                    merged_data[(addr_block, addr_page)].update(
                    {
                        'RD_LAT': latency_ns,
                        'RD_BAD_BITS': bad_bits,
                    })
                    if EXCLUDE_WR_FAILS and merged_data[(addr_block, addr_page)]['WR_FAIL'] != 0:
                        merged_data[(addr_block, addr_page)].update(
                        {
                            'RD_LAT': -latency_ns,
                            'RD_BAD_BITS': -bad_bits,
                        })
                elif oper_type_i == oER:
                    merged_data[(addr_block, addr_page)].update(
                    {
                        'ER_LAT': latency_ns,
                        'ER_FAIL': fail_info_E,
                    })

                '''
                # FO: Coverted Output =======================================
                if(data[4] == 0xEE):
                    if(oper_type_i in (oWR,oER) ): bad_bits = fail_info # WR/ER --> fail bit
                    log_str=((fmt_fo+'\n')%( oper_type,
                                             addr_block, addr_page,
                                             latency_ns, bad_bits, page_type, addr_shared_page) )
                    log_pr=(  fmt_pr      %( oper_type,
                                             addr_block, addr_page,
                                             latency_ns, bad_bits, page_type, addr_shared_page ) )
                else:
                    log_pr  = ' ... data corrupt! ...'
                    log_str = log_pr + '\n'

                # print(log_pr)
                #fo.write(log_str)
                '''

                # FS: Statistics Output ======================================
                # Latency --- always =========================================
                if( oper_type_i in (oWR, oRD, oER) ): # Latency --- when writeZ
                    if last_oper_type_i != oper_type_i: #reset
                        if( last_oper_type_i != oNONE ):
                            if( last_oper_type_i != oER ): #Erase --> only one!
                                for x in range(len(block_lats)):
                                    block_lats[x].write_file_stat(fl)
                            block_lat.write_file_stat(fl)
                        block_lats = [stat('block_'+oper_type+'_pt0_'+str(addr_block),7500000,60000),\
                                      stat('block_'+oper_type+'_pt1_'+str(addr_block),7500000,60000),\
                                      stat('block_'+oper_type+'_pt2_'+str(addr_block),7500000,60000)]
                        block_lat = stat('block_'+oper_type+'_all_'+str(addr_block),7500000,60000)

                        last_oper_type_i = oper_type_i
                    if( oper_type_i == oER ):
                        all_lats[oper_type_i][0].add(latency_ns)
                    else:
                        all_lats[oper_type_i][page_type].add(latency_ns)
                    block_lats[page_type].add(latency_ns)
                    all_lat.add(latency_ns)
                    block_lat.add(latency_ns)


                # BER --- only when read =====================================
                if(data[0] == oRD):
                    if addr_block == last_block+1: #reset
                        block_stat.write_file_stat(fs)
                        block_filtered_stat.write_file_stat(fsf)
                        if( block_filtered_stat.get_stat()['cnt']<BAD_BLOCK_THRESHOLD ): bad_blocks.append(last_block)
                        if( block_stat.get_stat()['sum']<2500 ): good_blocks.append(last_block)
                    if addr_block == last_block+1 or last_block == -1: #reset
                        if last_block == -1: last_block = addr_block
                        block_stat = stat('block_'+str(addr_block))
                        block_filtered_stat = stat('block_filtered_'+str(addr_block),BAD_BITS_THRESHOLD,BAD_BITS_THRESHOLD/10)
                        last_block = addr_block

                    all_stat.add(bad_bits)
                    block_stat.add(bad_bits)
                    # if(bad_bits < BAD_BITS_THRESHOLD):
                    if(merged_data[(addr_block,addr_page)].get('WR_FAIL',0)==0):
                        all_filtered_stat.add(bad_bits)
                        block_filtered_stat.add(bad_bits)

            #print final block stat (one more!)
            # latency
            for x in range(len(block_lats)):
                block_lats[x].write_file_stat(fl)
            block_lat.write_file_stat(fl)
            # BER
            block_stat.write_file_stat(fs)
            block_filtered_stat.write_file_stat(fsf)

            #print all stat
            # latency
            for x in range(len(all_lats)):
                for y in range(len(all_lats[x])):
                    all_lats[x][y].write_file_stat(fl)
            all_lat.write_file_stat(fl)

            # BER
            all_stat.write_file_stat(fs)
            all_filtered_stat.write_file_stat(fsf)
            fsf.write('BadBlocks_'+str(BAD_BLOCK_THRESHOLD)+'bits,'+str(bad_blocks)[1:-1]+'\n')

            #merged output
            for value in merged_seq : # HDR ####################
                fo.write(value+',')
            fo.write('\n')
            for (block,page) in sorted(merged_data): # Data ####################
                #if not (block in good_blocks): continue
                fo.write( '%d,%d,'%(block,page) )
                for value in merged_seq[2:] : # skip BLK,PG
                    if( value in merged_data[(block,page)] ):
                        fo.write( str(merged_data[(block,page)][value]) + ',' )
                    else:
                        fo.write( ' ,' )
                fo.write('\n')


            # summary print - BER
            '''
            ber_page_summary = [stat('page'+str(x)) for x in range(384)]
            for (block,page) in merged_data:
                sBER  = merged_data[(block,page)].get('RD_BAD_BITS', -1)
                if sBER > 10000: continue
                ber_page_summary[ page ].add(sBER)

            fx.write('Page, Avg_BadBits\n')
            for i in range(384) :
                fx.write('%d, %s\n'%(i, ber_page_summary[i].getAvgStr()))
            fx.write('\n\n\n')
            '''

            # summary print - ALL LAT
            wlat_summary = [ stat('wlat-lsb'), stat('wlat-csb'), stat('wlat-msb')]
            rlat_summary = [ stat('rlat-lsb'), stat('rlat-csb'), stat('rlat-msb')]
            elat_summary = [ stat('elat-lsb'), stat('elat-csb'), stat('elat-msb')]
            ber_summary = [ stat('ber-lsb'), stat('ber-csb'), stat('ber-msb')]
            for (block,page) in merged_data:
                if merged_data[(block,page)].get('RD_BAD_BITS', -1) > 10000: continue
                sPT = merged_data[(block,page)].get('PAGE_TYPE', -1)
                sWLAT = merged_data[(block,page)].get('WR_LAT', -1)
                sRLAT = merged_data[(block,page)].get('RD_LAT', -1)
                sELAT = merged_data[(block,page)].get('ER_LAT', -1)
                sBER  = merged_data[(block,page)].get('RD_BAD_BITS', -1)
                if 0<=sPT<=2:
                    if sWLAT>=0:
                        wlat_summary[ sPT ].add(sWLAT)
                    if sRLAT>=0:
                        rlat_summary[ sPT ].add(sRLAT)
                    if sELAT>=0:
                        elat_summary[ sPT ].add(sELAT)
                    if sBER>=0:
                        ber_summary[ sPT ].add(sBER)


            if True:
                fx.write('  ,       , WR_LAT, RD_LAT, RD_BAD_BITS, ER_LAT\n')
                fx.write('%s, LSB, %s, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), rlat_summary[0].getAvgStr(), ber_summary[0].getAvgStr(), elat_summary[0].getAvgStr()  ))
                fx.write('%s, CSB, %s, %s, %s, %s\n'%(       file, wlat_summary[1].getAvgStr(), rlat_summary[1].getAvgStr(), ber_summary[1].getAvgStr(), elat_summary[1].getAvgStr() ))
                fx.write('%s, MSB, %s, %s, %s, %s\n'%(       file, wlat_summary[2].getAvgStr(), rlat_summary[2].getAvgStr(), ber_summary[2].getAvgStr(), elat_summary[2].getAvgStr() ))
            else: #x-y inversed
                fx.write('  ,       , LSB, CSB, MSB\n')
                fx.write('%s, WR_LAT, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), wlat_summary[1].getAvgStr(), wlat_summary[2].getAvgStr() ))
                fx.write('%s, RD_LAT, %s, %s, %s\n'%(       file, rlat_summary[0].getAvgStr(), rlat_summary[1].getAvgStr(), rlat_summary[2].getAvgStr() ))
                fx.write('%s, ER_LAT, %s, %s, %s\n'%(       file, elat_summary[0].getAvgStr(), elat_summary[1].getAvgStr(), elat_summary[2].getAvgStr() ))
                fx.write('%s, RD_BAD_BITS, %s, %s, %s\n\n'%(file,  ber_summary[0].getAvgStr(),  ber_summary[1].getAvgStr(),  ber_summary[2].getAvgStr() ))

            # summary print - EVEN LAT
            wlat_summary = [ stat('wlat-lsb'), stat('wlat-csb'), stat('wlat-msb')]
            rlat_summary = [ stat('rlat-lsb'), stat('rlat-csb'), stat('rlat-msb')]
            elat_summary = [ stat('elat-lsb'), stat('elat-csb'), stat('elat-msb')]
            ber_summary = [ stat('ber-lsb'), stat('ber-csb'), stat('ber-msb')]
            for (block,page) in merged_data:
                if page%2==1: continue
                if merged_data[(block,page)].get('RD_BAD_BITS', -1) > 10000: continue
                sPT = merged_data[(block,page)].get('PAGE_TYPE', -1)
                sWLAT = merged_data[(block,page)].get('WR_LAT', -1)
                sRLAT = merged_data[(block,page)].get('RD_LAT', -1)
                sELAT = merged_data[(block,page)].get('ER_LAT', -1)
                sBER  = merged_data[(block,page)].get('RD_BAD_BITS', -1)
                if 0<=sPT<=2:
                    if sWLAT>=0:
                        wlat_summary[ sPT ].add(sWLAT)
                    if sRLAT>=0:
                        rlat_summary[ sPT ].add(sRLAT)
                    if sELAT>=0:
                        elat_summary[ sPT ].add(sELAT)
                    if sBER>=0:
                        ber_summary[ sPT ].add(sBER)


            if True:
                fx.write('EVEN Page (Left),       , WR_LAT, RD_LAT, RD_BAD_BITS, ER_LAT\n')
                fx.write('%s, LSB, %s, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), rlat_summary[0].getAvgStr(), ber_summary[0].getAvgStr(), elat_summary[0].getAvgStr()  ))
                fx.write('%s, CSB, %s, %s, %s, %s\n'%(       file, wlat_summary[1].getAvgStr(), rlat_summary[1].getAvgStr(), ber_summary[1].getAvgStr(), elat_summary[1].getAvgStr() ))
                fx.write('%s, MSB, %s, %s, %s, %s\n'%(       file, wlat_summary[2].getAvgStr(), rlat_summary[2].getAvgStr(), ber_summary[2].getAvgStr(), elat_summary[2].getAvgStr() ))
            else: #x-y inversed
                fx.write('  ,       , LSB, CSB, MSB\n')
                fx.write('%s, WR_LAT, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), wlat_summary[1].getAvgStr(), wlat_summary[2].getAvgStr() ))
                fx.write('%s, RD_LAT, %s, %s, %s\n'%(       file, rlat_summary[0].getAvgStr(), rlat_summary[1].getAvgStr(), rlat_summary[2].getAvgStr() ))
                fx.write('%s, ER_LAT, %s, %s, %s\n'%(       file, elat_summary[0].getAvgStr(), elat_summary[1].getAvgStr(), elat_summary[2].getAvgStr() ))
                fx.write('%s, RD_BAD_BITS, %s, %s, %s\n\n'%(file,  ber_summary[0].getAvgStr(),  ber_summary[1].getAvgStr(),  ber_summary[2].getAvgStr() ))

            # summary print - ODD LAT
            wlat_summary = [ stat('wlat-lsb'), stat('wlat-csb'), stat('wlat-msb')]
            rlat_summary = [ stat('rlat-lsb'), stat('rlat-csb'), stat('rlat-msb')]
            elat_summary = [ stat('elat-lsb'), stat('elat-csb'), stat('elat-msb')]
            ber_summary = [ stat('ber-lsb'), stat('ber-csb'), stat('ber-msb')]
            for (block,page) in merged_data:
                if page%2==0: continue
                if merged_data[(block,page)].get('RD_BAD_BITS', -1) > 10000: continue
                sPT = merged_data[(block,page)].get('PAGE_TYPE', -1)
                sWLAT = merged_data[(block,page)].get('WR_LAT', -1)
                sRLAT = merged_data[(block,page)].get('RD_LAT', -1)
                sELAT = merged_data[(block,page)].get('ER_LAT', -1)
                sBER  = merged_data[(block,page)].get('RD_BAD_BITS', -1)
                if 0<=sPT<=2:
                    if sWLAT>=0:
                        wlat_summary[ sPT ].add(sWLAT)
                    if sRLAT>=0:
                        rlat_summary[ sPT ].add(sRLAT)
                    if sELAT>=0:
                        elat_summary[ sPT ].add(sELAT)
                    if sBER>=0:
                        ber_summary[ sPT ].add(sBER)


            if True:
                fx.write('ODD Page (Right),       , WR_LAT, RD_LAT, RD_BAD_BITS, ER_LAT\n')
                fx.write('%s, LSB, %s, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), rlat_summary[0].getAvgStr(), ber_summary[0].getAvgStr(), elat_summary[0].getAvgStr()  ))
                fx.write('%s, CSB, %s, %s, %s, %s\n'%(       file, wlat_summary[1].getAvgStr(), rlat_summary[1].getAvgStr(), ber_summary[1].getAvgStr(), elat_summary[1].getAvgStr() ))
                fx.write('%s, MSB, %s, %s, %s, %s\n'%(       file, wlat_summary[2].getAvgStr(), rlat_summary[2].getAvgStr(), ber_summary[2].getAvgStr(), elat_summary[2].getAvgStr() ))
            else: #x-y inversed
                fx.write('  ,       , LSB, CSB, MSB\n')
                fx.write('%s, WR_LAT, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), wlat_summary[1].getAvgStr(), wlat_summary[2].getAvgStr() ))
                fx.write('%s, RD_LAT, %s, %s, %s\n'%(       file, rlat_summary[0].getAvgStr(), rlat_summary[1].getAvgStr(), rlat_summary[2].getAvgStr() ))
                fx.write('%s, ER_LAT, %s, %s, %s\n'%(       file, elat_summary[0].getAvgStr(), elat_summary[1].getAvgStr(), elat_summary[2].getAvgStr() ))
                fx.write('%s, RD_BAD_BITS, %s, %s, %s\n\n'%(file,  ber_summary[0].getAvgStr(),  ber_summary[1].getAvgStr(),  ber_summary[2].getAvgStr() ))

                                
            # summary print - EVEN BLOCK
            wlat_summary = [ stat('wlat-lsb'), stat('wlat-csb'), stat('wlat-msb')]
            rlat_summary = [ stat('rlat-lsb'), stat('rlat-csb'), stat('rlat-msb')]
            elat_summary = [ stat('elat-lsb'), stat('elat-csb'), stat('elat-msb')]
            ber_summary = [ stat('ber-lsb'), stat('ber-csb'), stat('ber-msb')]
            for (block,page) in merged_data:
                if block%2==1: continue
                if merged_data[(block,page)].get('RD_BAD_BITS', -1) > 10000: continue
                sPT = merged_data[(block,page)].get('PAGE_TYPE', -1)
                sWLAT = merged_data[(block,page)].get('WR_LAT', -1)
                sRLAT = merged_data[(block,page)].get('RD_LAT', -1)
                sELAT = merged_data[(block,page)].get('ER_LAT', -1)
                sBER  = merged_data[(block,page)].get('RD_BAD_BITS', -1)
                if 0<=sPT<=2:
                    if sWLAT>=0:
                        wlat_summary[ sPT ].add(sWLAT)
                    if sRLAT>=0:
                        rlat_summary[ sPT ].add(sRLAT)
                    if sELAT>=0:
                        elat_summary[ sPT ].add(sELAT)
                    if sBER>=0:
                        ber_summary[ sPT ].add(sBER)


            if True:
                fx.write('EVEN Block (Left),       , WR_LAT, RD_LAT, RD_BAD_BITS, ER_LAT\n')
                fx.write('%s, LSB, %s, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), rlat_summary[0].getAvgStr(), ber_summary[0].getAvgStr(), elat_summary[0].getAvgStr()  ))
                fx.write('%s, CSB, %s, %s, %s, %s\n'%(       file, wlat_summary[1].getAvgStr(), rlat_summary[1].getAvgStr(), ber_summary[1].getAvgStr(), elat_summary[1].getAvgStr() ))
                fx.write('%s, MSB, %s, %s, %s, %s\n'%(       file, wlat_summary[2].getAvgStr(), rlat_summary[2].getAvgStr(), ber_summary[2].getAvgStr(), elat_summary[2].getAvgStr() ))
            else: #x-y inversed
                fx.write('  ,       , LSB, CSB, MSB\n')
                fx.write('%s, WR_LAT, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), wlat_summary[1].getAvgStr(), wlat_summary[2].getAvgStr() ))
                fx.write('%s, RD_LAT, %s, %s, %s\n'%(       file, rlat_summary[0].getAvgStr(), rlat_summary[1].getAvgStr(), rlat_summary[2].getAvgStr() ))
                fx.write('%s, ER_LAT, %s, %s, %s\n'%(       file, elat_summary[0].getAvgStr(), elat_summary[1].getAvgStr(), elat_summary[2].getAvgStr() ))
                fx.write('%s, RD_BAD_BITS, %s, %s, %s\n\n'%(file,  ber_summary[0].getAvgStr(),  ber_summary[1].getAvgStr(),  ber_summary[2].getAvgStr() ))

            # summary print - ODD BLOCK
            wlat_summary = [ stat('wlat-lsb'), stat('wlat-csb'), stat('wlat-msb')]
            rlat_summary = [ stat('rlat-lsb'), stat('rlat-csb'), stat('rlat-msb')]
            elat_summary = [ stat('elat-lsb'), stat('elat-csb'), stat('elat-msb')]
            ber_summary = [ stat('ber-lsb'), stat('ber-csb'), stat('ber-msb')]
            for (block,page) in merged_data:
                if block%2==0: continue
                if merged_data[(block,page)].get('RD_BAD_BITS', -1) > 10000: continue
                sPT = merged_data[(block,page)].get('PAGE_TYPE', -1)
                sWLAT = merged_data[(block,page)].get('WR_LAT', -1)
                sRLAT = merged_data[(block,page)].get('RD_LAT', -1)
                sELAT = merged_data[(block,page)].get('ER_LAT', -1)
                sBER  = merged_data[(block,page)].get('RD_BAD_BITS', -1)
                if 0<=sPT<=2:
                    if sWLAT>=0:
                        wlat_summary[ sPT ].add(sWLAT)
                    if sRLAT>=0:
                        rlat_summary[ sPT ].add(sRLAT)
                    if sELAT>=0:
                        elat_summary[ sPT ].add(sELAT)
                    if sBER>=0:
                        ber_summary[ sPT ].add(sBER)


            if True:
                fx.write('ODD Block (Right),       , WR_LAT, RD_LAT, RD_BAD_BITS, ER_LAT\n')
                fx.write('%s, LSB, %s, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), rlat_summary[0].getAvgStr(), ber_summary[0].getAvgStr(), elat_summary[0].getAvgStr()  ))
                fx.write('%s, CSB, %s, %s, %s, %s\n'%(       file, wlat_summary[1].getAvgStr(), rlat_summary[1].getAvgStr(), ber_summary[1].getAvgStr(), elat_summary[1].getAvgStr() ))
                fx.write('%s, MSB, %s, %s, %s, %s\n'%(       file, wlat_summary[2].getAvgStr(), rlat_summary[2].getAvgStr(), ber_summary[2].getAvgStr(), elat_summary[2].getAvgStr() ))
            else: #x-y inversed
                fx.write('  ,       , LSB, CSB, MSB\n')
                fx.write('%s, WR_LAT, %s, %s, %s\n'%(       file, wlat_summary[0].getAvgStr(), wlat_summary[1].getAvgStr(), wlat_summary[2].getAvgStr() ))
                fx.write('%s, RD_LAT, %s, %s, %s\n'%(       file, rlat_summary[0].getAvgStr(), rlat_summary[1].getAvgStr(), rlat_summary[2].getAvgStr() ))
                fx.write('%s, ER_LAT, %s, %s, %s\n'%(       file, elat_summary[0].getAvgStr(), elat_summary[1].getAvgStr(), elat_summary[2].getAvgStr() ))
                fx.write('%s, RD_BAD_BITS, %s, %s, %s\n\n'%(file,  ber_summary[0].getAvgStr(),  ber_summary[1].getAvgStr(),  ber_summary[2].getAvgStr() ))
                                                    
                                                    


            # save it
            #fo.write(data)
            fo.close()
            fs.close()
            fsf.close()
            fl.close()

    fx.close()

if __name__ == '__main__': main()
