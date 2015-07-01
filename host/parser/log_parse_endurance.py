
import fileinput
import sys
import os
import re
import struct

### Packet Format ###
SIZE_PACKET = 12
FMT_PACKET = '>BIIHB'
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
merged_seq_WR = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','WR_LAT']
merged_seq_WR2 = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','WR_FAIL']
merged_seq_RD = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','RD_LAT']
merged_seq_RD2 = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','RD_BAD_BITS']
merged_seq_ER = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','ER_LAT']
merged_seq_ER2 = ['BLK','PG','PAGE_TYPE','PAGE_GROUP','ER_FAIL']
merged_seq = [ merged_seq_WR, merged_seq_WR2, merged_seq_RD, merged_seq_RD2, merged_seq_ER, merged_seq_ER2 ]

ONLY_AVG = True #False

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



def main():
    print('[INFO] Open FPGA NVM Endurance Log Parser')

    fo_name = None
    fo = None
    merged_data = None
    file_number = 0

    for file in sorted(sys.argv[1:]):
        with open(file, 'rb') as fi: # Load result binary file

            if not fo_name:
                fo_name = file+'_endurance.csv'
            if not fo:
                fo = open(fo_name, 'wb') # Converted file
                print('[INFO] OUTPUT   : %s'%fo_name)
            print(    '[INFO] INPUT %02d : %s'%(file_number,file))
            file_number+=1


            if(SIZE_PACKET != struct.calcsize(FMT_PACKET)):
                print("Please Verify Packet Format")
                return

            bin = fi.read()
            fi.close()
            print('... File Loaded')

            offset = 0;

            if not merged_data:
                merged_data = {}
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

################# Merged_data process #############################################################
                if not ( (addr_block, addr_page) in merged_data ):
                    merged_data.update({ (addr_block, addr_page) : {} })
                    merged_data[(addr_block, addr_page)].update(
                    { 'PAGE_TYPE': page_type,
                      'PAGE_GROUP':addr_shared_page,
                    })

                cur_data = merged_data[(addr_block, addr_page)]
                if oper_type_i == oWR:
                    cur_data.update(
                    {
                        'WR_LAT':  cur_data.get('WR_LAT',[]) +[latency_ns],
                        'WR_FAIL': cur_data.get('WR_FAIL',[])+[fail_info_W],
                    })
                elif oper_type_i == oRD:
                    cur_data.update(
                    {
                        'RD_LAT':      cur_data.get('RD_LAT',[])     +[latency_ns],
                        'RD_BAD_BITS': cur_data.get('RD_BAD_BITS',[])+[bad_bits],
                    })
                elif oper_type_i == oER:
                    cur_data.update(
                    {
                        'ER_LAT':  cur_data.get('ER_LAT',[]) +[latency_ns],
                        'ER_FAIL': cur_data.get('ER_FAIL',[])+[fail_info_E],
                    })
            print('... File Parsed')



    #merged output
    for seq in merged_seq:
        # COMMON HDR ####################
        for value in seq[:4] :
            fo.write(value+',')

        # ENDURANCE HDR ####################
        for (block,page) in sorted(merged_data):
            length = len(merged_data[(block,page)][seq[4]])
            break
        for value in seq[4:] :
            for x in range(length):
                fo.write(value+str(x)+',')
        fo.write('\n')

        avg = {}
        avg_pt = [{},{},{}]
        # DATA ####################
        for (block,page) in sorted(merged_data):
            if not seq[4] in merged_data[(block,page)]: continue
            if not ONLY_AVG: fo.write( '%d,%d,'%(block,page) )
            for value in seq[2:4] : # for items which are not array
                if( value in merged_data[(block,page)] ):
                    if not ONLY_AVG: fo.write( str(merged_data[(block,page)][value]) + ',' )
            for value in seq[4:] : # array items
                if not (value in avg):
                    avg.update( { value : [stat('') for x in range(length)] } )
                    for y in range(3):
                        avg_pt[y].update( { value : [stat('') for x in range(length)] } )

                for x in range( len(merged_data[(block,page)][value]) ):
                    avg[value][x].add( merged_data[(block,page)][value][x] )
                    avg_pt[ merged_data[(block,page)]['PAGE_TYPE'] ][value][x].add( merged_data[(block,page)][value][x] )
                    if not ONLY_AVG: fo.write( str(merged_data[(block,page)][value][x]) + ',' )
            if not ONLY_AVG: fo.write('\n')

        fo.write('All,,,,')
        for value in seq[4:] :
            for x in range(length):
                fo.write( str(float(float(avg[value][x].sum) / float(avg[value][x].cnt)))+',')
        fo.write('\n')

        for y in range(3):
            fo.write('All_pt'+str(y)+',,,,')
            for value in seq[4:]:
                for x in range(length):
                    if(avg_pt[y][value][x].cnt == 0):
                        fo.write(',')
                        continue
                    fo.write( str(float(float(avg_pt[y][value][x].sum) / float(avg_pt[y][value][x].cnt)))+',' )
            fo.write('\n')
        fo.write('\n\n\n')
                    


    # save it
    #fo.write(data)
    fo.close()

if __name__ == '__main__': main()
