import serial
import time
import struct
import binascii
import serial.tools.list_ports
import threading
import winsound

from Tkinter import *
from tkFileDialog import askopenfilename
import ttk

cfg_file = 'ofserial.cfg'
global_config = { 'COM_PORT' : 'COM1' }

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

actions = [
    {
        'NAME' : 'cap_0E-ALL',
        'CMDS' : [ uHALT(),
                   uADDR(0x089,0x08F),
                   uOPER(oWR=False, oRD=False, oER=True, oRST=True),
                   uLOOP(1),
                   uLOG(0),
                   uNAND(pLSB=True, pCSB=True, pMSB=True),
                   uSTART() ]
    }
]

slow_serial = 0

class Checkbar(Frame):
   def __init__(self, parent=None, picks=[], side=LEFT, anchor=W):
      Frame.__init__(self, parent)
      self.vars = []
      for pick in picks:
         var = IntVar()
         chk = Checkbutton(self, text=pick, variable=var)
         chk.pack(side=side, anchor=anchor, expand=YES)
         self.vars.append(var)
   def state(self):
      return map((lambda var: var.get()), self.vars)


class App:
    # ================== SETUP LOAD/SAVE ==================
    def app_setup(self):
        global global_config
        global actions

        with open(cfg_file, 'rb') as fc:
            print 'load', cfg_file
            exec( str(fc.read()) ) in globals()
            fc.close()
        self.load_action()

    def load_action(self):
        act_file = global_config.get('CMD_FILE','ofserial.act')
        with open(act_file, 'rb') as fa:
            print 'load', act_file
            exec( fa.read() ) in globals()
            fa.close()

    def log(self, *args):
        s = ''
        for arg in args:
            if args.index(arg) != 0: s+= ', '
            s += str(arg)
        print s
        if self.txt_LOG.size()>1024:
            self.txt_LOG.delete(0)
        self.txt_LOG.insert( END, s );
        self.txt_LOG.yview_scroll( 1, UNITS )

    def file_selector(self,which_file=0):
        if( which_file == 0):
            name = askopenfilename(filetypes=[('Action files', '.act'),('all files', '.*')])
            if name:
                print which_file, name
                global_config.update( {'CMD_FILE': name })
                self.load_action()

    # ================== COM PORT ==================
    def serial_setup(self):
        self.sp = None
        self.com_port_selected = StringVar()
        self.com_port_list = []
        com_ports = list( serial.tools.list_ports.comports() )
        for com_port in com_ports :
            self.com_port_list.append(str(com_port[0]))

        self.cmb_COM.configure(values=self.com_port_list, textvariable=self.com_port_selected)

        if global_config['COM_PORT'] in self.com_port_list:
            self.log( 'open default %s'%global_config['COM_PORT'] )
            self.serial_open( global_config['COM_PORT'] )
        else:
            self.log( 'can not find default %s'%global_config['COM_PORT'] )

    def serial_open(self, com_port_num=None):
        if self.sp == None:
            if com_port_num == None:
                self.com_port_selected = self.cmb_COM.get()
                com_port_num = str(self.com_port_selected)

            self.log( 'COM OPEN %s'%com_port_num )
            self.sp = serial.Serial(com_port_num, 115200, timeout=3)

            self.cmb_COM.current(self.com_port_list.index(com_port_num))
            self.btn_toggle()

    def serial_close(self):
        if self.sp != None:
            self.log( 'COM CLOSE' )

            self.sp.close()
            self.sp = None

            self.btn_toggle()

    # ================= COM ACTION ==================
    def serial_start(self):
        self.btn_toggle(running=1)
        def handle_thread():
            self.log('[INFO] TXFR DATA')
            for action in actions:
                #SEND COMMANDS
                aname    = action['NAME']
                commands = action['CMDS']
                for command in commands:
                    self.log( commands.index(command), binascii.hexlify(bytearray(command)) )
                    if slow_serial == 0:
                        self.sp.write( command )
                    else:
                        for i in range(12):
                            self.sp.write( bytearray([ command[i] ]) )
                            time.sleep(slow_serial)

                #RECV RESULT
                fo_name = aname + '.bin'
                self.log('[INFO] RCVD DATA, LOG_FILE: %s'%(fo_name))
                fo = None
                total_rcvd_byte = 0
                while True:
                    rcvd_data = self.sp.read( self.sp.inWaiting()+1 )
                    if len(rcvd_data)==0 and total_rcvd_byte > 14: break
                    total_rcvd_byte += len(rcvd_data)
                    # self.log( len(rcvd_data), binascii.hexlify(bytearray(rcvd_data)) )
                    if fo == None: fo = open(fo_name, 'wb')
                    fo.write(rcvd_data)

                if fo != None:
                    self.log('[INFO] CLOSE LOG_FILE: %s, BYTES: %d, PACKETS: %d, LEFTBYTES: %d'%(fo_name, total_rcvd_byte, total_rcvd_byte/14, total_rcvd_byte%14))
                    fo.close()
            self.log('[INFO] FINISHED')
            self.btn_toggle(running=0)
            winsound.Beep(440, 1500)
        threading.Thread(target=handle_thread).start()

    def serial_stop(self):
        self.log('[INFO] Sorry, NOT yet implemented :(')
        pass

    def test_btn(self):
        for i in range(512):
            self.log('Test%d'%i)


    # ================== UI ==================
    def btn_toggle(self, running=0):
        if self.sp == None:
            self.btn_COMOPEN.configure(state=NORMAL)
            self.btn_COMCLOSE.configure(state=DISABLED)
            self.btn_START.configure(state=DISABLED)
            self.btn_STOP.configure(state=DISABLED)
        else:
            self.btn_COMOPEN.configure(state=DISABLED)
            self.btn_COMCLOSE.configure(state=NORMAL)
            if running:
                self.btn_START.configure(state=DISABLED)
                self.btn_STOP.configure(state=NORMAL)
            else:
                self.btn_START.configure(state=NORMAL)
                self.btn_STOP.configure(state=DISABLED)

    def __init__(self, top):
        self.app_setup()     # Load Config File

        master = Frame(top, padx=10, pady=10)
        master.pack()

        # COM PORT =====
        frame = Frame(master, relief='ridge', borderwidth=3)
        frame.pack(side=TOP, fill=X)
        Label(frame, text="COM PORT", bg="blue", fg="white").pack(side=LEFT)
        self.cmb_COM = ttk.Combobox(frame, exportselection=0)
        self.cmb_COM.pack(side=LEFT)
        self.btn_COMOPEN = Button(frame, text="OPEN", fg="green", command=self.serial_open)
        self.btn_COMOPEN.pack(side=LEFT)
        self.btn_COMCLOSE = Button(frame, text="CLOSE", fg="red", command=self.serial_close)
        self.btn_COMCLOSE.pack(side=LEFT)


        # LOG =====
        frame = Frame(master, relief='ridge', borderwidth=3)
        frame.pack(side=TOP,fill=X)
        self.txt_LOG_yScroll = Scrollbar(frame, orient=VERTICAL)
        Label(frame, text="LOG", bg="green", fg="black").pack(side=LEFT, fill=BOTH)
        self.txt_LOG = Listbox(frame, height=32, width=128, yscrollcommand=self.txt_LOG_yScroll.set)
        self.txt_LOG.pack(side=LEFT,fill=X)

        self.txt_LOG_yScroll.pack(side=LEFT, fill=Y)

        # FILE CONFIG =====
        frame = Frame(master, relief='ridge', borderwidth=3)
        frame.pack(side=TOP,fill=X)
        Label(frame, text="FILES", bg="black", fg="white").pack(side=LEFT)
        self.btn_FILE = Button(frame, text='...', command=self.file_selector)
        self.btn_FILE.pack(side=LEFT,fill=X)

        # EVENT CONFIG =====
        frame = Frame(master, relief='ridge', borderwidth=3)
        frame.pack(side=TOP,fill=X)
        Label(frame, text="CMDS", bg="red", fg="yellow").pack(side=LEFT)

        # CONTROL =====
        frame = Frame(master, relief='ridge', borderwidth=3)
        frame.pack(side=TOP,fill=X)
        Label(frame, text="CONTROL", bg="white", fg="black").pack(side=LEFT, fill=BOTH)
        self.btn_START = Button(frame, text="START", fg="black", bg="green", command=self.serial_start)
        self.btn_START.pack(side=LEFT)
        self.btn_STOP = Button(frame, text="STOP", fg="white", bg="red", command=self.serial_stop)
        self.btn_STOP.pack(side=LEFT)
        self.btn_TEST = Button(frame, text="TEST", fg="white", bg="blue", command=self.test_btn)
        self.btn_TEST.pack(side=LEFT)


        # RUN THREAD =====
        self.serial_setup()  # serial setup

        self.btn_toggle()

        '''
        Label(frame, text="Red Sun", bg="red", fg="white").pack(side=LEFT)
        self.button = Button(frame, 
                             text="QUIT", fg="red",
                             command=frame.quit)
        self.button.pack(side=RIGHT)

        frame = Frame(master)
        frame.pack(side=TOP)
        Label(frame, text="Green Grass", bg="green", fg="black").pack(side=LEFT)
        self.slogan = Button(frame,
                             text="Hello",
                             command=self.write_slogan)
        self.slogan.pack(side=RIGHT)

        frame = Frame(master)
        frame.pack(side=TOP)

        Label(frame, text="Blue Sky", bg="blue", fg="white").pack(side=LEFT)
        self.lng = Checkbar(frame, ['Python', 'Ruby', 'Perl', 'C++'])
        self.tgl = Checkbar(frame, ['English','German'])
        self.lng.pack(side=RIGHT,  fill=X)
        self.tgl.pack(side=RIGHT)
        self.errmsg = 'Error!'
        self.filebtn = Button(frame, text='File Open', command=callback)
        self.filebtn.pack(side=RIGHT,fill=X)
        self.cmbox = ttk.Combobox(frame, values=['COM0', 'COM1'])
        self.cmbox.pack(side=RIGHT)
        '''

'''
  def write_slogan(self):
    print "Tkinter is easy to use!"
'''


root = Tk()
app = App(root)
root.mainloop()
