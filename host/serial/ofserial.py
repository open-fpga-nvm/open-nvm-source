import serial
import time
import struct
import binascii
import serial.tools.list_ports

slow_serial = 0
fo_name     = 'cap_serial.bin'

#Packet Generators

# parameter uADDR = 8'h00, uOPER = 8'h01, uLOOP = 8'h02, uLOG = 8'h03,
#           uNAND = 8'h04, uMRAM = 8'h05,
#           uSTART= 8'hF0, uHALT = 8'hF1;

def uADDR(addr1, addr2):
    return struct.pack('>BIIHB', 0x00, addr1, addr2, 0, 0xEE)

def uOPER(oWR, oRD, oER, oRST):
    mOPER = 0x0
    if oWR : mOPER |= 0x01
    if oRD : mOPER |= 0x02
    if oER : mOPER |= 0x04
    if oRST: mOPER |= 0x08
    return struct.pack('>BBBBBIHB', 0x01, mOPER,0,0,0, 0, 0, 0xEE)

def uLOOP(loop_count):
    return struct.pack('>BIIHB', 0x02, loop_count, 0, 0, 0xEE)

def uLOG(log_freq2):
    return struct.pack('>BIIHB', 0x03, log_freq2, 0, 0, 0xEE)

def uNAND(pLSB, pCSB, pMSB, ptrn_usr0=0, ptrn_usr1=0, ptrn0=0, ptrn1=0xFF):
    mPAGETYPE = 0
    if pLSB : mPAGETYPE |= 0x01
    if pCSB : mPAGETYPE |= 0x02
    if pMSB : mPAGETYPE |= 0x04
    return struct.pack('>BBBBBHHHB', 0x04,   mPAGETYPE, 0, ptrn_usr0, ptrn_usr1,   ptrn0, ptrn1,   0, 0xEE)

def uMRAM(addr1, addr2):
    return struct.pack('>BIIHB', 0x05, addr1, addr2, 0, 0xEE)

def uSTART():
    return struct.pack('>BIIHB', 0xF0, 0, 0, 0, 0xEE)

def uHALT():
    return struct.pack('>BIIHB', 0xF1, 0, 0, 0, 0xEE)

def main():
    print('[INFO] Open FPGA NVM Serial Controller')

    com_ports = list( serial.tools.list_ports.comports() )
    for com_port in com_ports :
        print com_port[0]
    return

    params = [ uHALT(),
               uADDR(0x089,0x08F),
               uOPER(oWR=True, oRD=True, oER=True, oRST=True),
               uLOOP(1),
               uLOG(0),
               uNAND(pLSB=True, pCSB=True, pMSB=True),
               uSTART() ]

    sp = serial.Serial('COM5', 115200, timeout=3)

    
    print('[INFO] TXFR DATA')    
    for param in params :
        print params.index(param), binascii.hexlify(bytearray(param))
        if slow_serial == 0:
            sp.write( param )
        else:
            for i in range(12):
                sp.write( bytearray([ param[i] ]) )
                time.sleep(slow_serial)

    print('[INFO] RCVD DATA')
    fo = None
    while True:
        rcvd_data = sp.read( 12 )
        if len(rcvd_data)==0: break
        print len(rcvd_data), binascii.hexlify(bytearray(rcvd_data))
        if fo == None: fo = open(fo_name, 'wb')
        fo.write(rcvd_data)


    sp.close()

    print('[INFO] END')



if __name__ == '__main__': main()
