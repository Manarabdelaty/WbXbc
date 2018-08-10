//###############################################################################
//# WbXbc - Wishbone Crossbar Components - Pipelined to Standard Bus Gasket     #
//###############################################################################
//#    Copyright 2018 Dirk Heisswolf                                            #
//#    This file is part of the WbXbc project.                                  #
//#                                                                             #
//#    WbXbc is free software: you can redistribute it and/or modify            #
//#    it under the terms of the GNU General Public License as published by     #
//#    the Free Software Foundation, either version 3 of the License, or        #
//#    (at your option) any later version.                                      #
//#                                                                             #
//#    WbXbc is distributed in the hope that it will be useful,                 #
//#    but WITHOUT ANY WARRANTY; without even the implied warranty of           #
//#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
//#    GNU General Public License for more details.                             #
//#                                                                             #
//#    You should have received a copy of the GNU General Public License        #
//#    along with WbXbc.  If not, see <http://www.gnu.org/licenses/>.           #
//###############################################################################
//# Description:                                                                #
//#    This module connects a pipelined Wishbone initiator to a standard        #
//#    protocol target.                                                         #
//#                                                                             #
//#                          +-------------------+                              #
//#                          |                   |                              #
//#                          |                   |                              #
//#            pipelined     |       WbXbc       |    standard                  #
//#            initiator --->|    standardizer   |---> target                   #
//#               bus        |                   |      bus                     #
//#                          |                   |                              #
//#                          |                   |                              #
//#                          +-------------------+                              #
//#    Transaction timing:                                                      #
//#                                                                             #
//#                     :__   :__   :__   :__   :__   :__   :__   :__   :__     #
//#        clk_i      __|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__  #
//#                     :     :     :     :     :     :     :     :     :       #
//#    request from     :_____:_____:_____:     :_____:_____:     :     :_____  #  
//#    initiator      --|_____|___________|-----|___________|-----:-----|_____  # 
//#                     :     :stall:     :     :stall:     :     :     :stall  #  
//#    request to       :     :_____:     :_____:_____:     :_____:_____:_____  #  
//#    target         --:-----|_____|-----|___________|-----|_________________  #  
//#                     :     : reg :     : reg :     :     : reg :     :       #  
//#    response from    :     :_____:     :     :_____:     :     :     :_____  #  
//#    target         --:-----|_____|-----:-----|_____|-----|-----|-----|_____  #  
//#                     :     :     :     :noack:     :     :noack:noack:       #  
//#    response to      :     :_____:     :     :_____:     :     :     :_____  #  
//#    initiator      --:-----|_____|-----:-----|_____|-----:-----:-----|_____  #  
//#                     :     :     :     :     :     :     :     :     :       #
//#                                                                             #
//###############################################################################
//# Version History:                                                            #
//#   August 3, 2018                                                            #
//#      - Initial release                                                      #
//###############################################################################
`default_nettype none

module WbXbc_standardizer
  #(parameter ADDR_WIDTH  = 16, //width of the initiator address bus
    parameter DATA_WIDTH  = 16, //width of each initiator data bus
    parameter SEL_WIDTH   = 2,  //number of initiator write data select lines
    parameter TGA_WIDTH   = 1,  //number of propagated address tags
    parameter TGC_WIDTH   = 1,  //number of propagated cycle tags
    parameter TGRD_WIDTH  = 1,  //number of propagated read data tags
    parameter TGWD_WIDTH  = 1)  //number of propagated write data tags

   (//Clock and reset
    //---------------
    input wire                           clk_i,                               //module clock
    input wire                           async_rst_i,                         //asynchronous reset
    input wire                           sync_rst_i,                          //synchronous reset

    //Initiator interface
    //-------------------
    input  wire                          itr_cyc_i,                           //bus cycle indicator       +-
    input  wire                          itr_stb_i,                           //access request            |
    input  wire                          itr_we_i,                            //write enable              |
    input  wire                          itr_lock_i,                          //uninterruptable bus cycle | initiator
    input  wire [SEL_WIDTH-1:0]          itr_sel_i,                           //write data selects        | initiator
    input  wire [ADDR_WIDTH-1:0]         itr_adr_i,                           //address bus               | to
    input  wire [DATA_WIDTH-1:0]         itr_dat_i,                           //write data bus            | target
    input  wire [TGA_WIDTH-1:0]          itr_tga_i,                           //address tags              |
    input  wire [TGC_WIDTH-1:0]          itr_tgc_i,                           //bus cycle tags            |
    input  wire [TGWD_WIDTH-1:0]         itr_tgd_i,                           //write data tags           +-
    output wire                          itr_ack_o,                           //bus cycle acknowledge     +-
    output wire                          itr_err_o,                           //error indicator           | target
    output wire                          itr_rty_o,                           //retry request             | to
    output wire                          itr_stall_o,                         //access delay              | initiator
    output wire [DATA_WIDTH-1:0]         itr_dat_o,                           //read data bus             |
    output wire [TGRD_WIDTH-1:0]         itr_tgd_o,                           //read data tags            +-

    //Target interfaces
    //-----------------
    output wire                          tgt_cyc_o,                           //bus cycle indicator       +-
    output wire                          tgt_stb_o,                           //access request            |
    output wire                          tgt_we_o,                            //write enable              |
    output wire                          tgt_lock_o,                          //uninterruptable bus cycle |
    output wire [SEL_WIDTH-1:0]          tgt_sel_o,                           //write data selects        | initiator
    output wire [ADDR_WIDTH-1:0]         tgt_adr_o,                           //write data selects        | to
    output wire [DATA_WIDTH-1:0]         tgt_dat_o,                           //write data bus            | target
    output wire [TGA_WIDTH-1:0]          tgt_tga_o,                           //address tags              |
    output wire [TGC_WIDTH-1:0]          tgt_tgc_o,                           //bus cycle tags            |
    output wire [TGWD_WIDTH-1:0]         tgt_tgd_o,                           //write data tags           +-
    input  wire                          tgt_ack_i,                           //bus cycle acknowledge     +-
    input  wire                          tgt_err_i,                           //error indicator           | target
    input  wire                          tgt_rty_i,                           //retry request             | to
    input  wire                          tgt_stall_i,                         //access delay              | initiator
    input  wire [DATA_WIDTH-1:0]         tgt_dat_i,                           //read data bus             |
    input  wire [TGRD_WIDTH-1:0]         tgt_tgd_i);                          //read data tags            +-

   //Internal signals
   reg [1:0] 				 state_next;                          //next state

   //State variable
   reg  [1:0]                            state_reg;                           //state variable

   //Registered initiator request signals
   reg                                   itr_we_reg;                          //write enable              +-
   reg                                   itr_lock_reg;                        //uninterruptable bus cycle |
   reg  [SEL_WIDTH-1:0]                  itr_sel_reg;                         //write data selects        | initiator
   reg  [ADDR_WIDTH-1:0]                 itr_adr_reg;                         //address bus               | to
   reg  [DATA_WIDTH-1:0]                 itr_dat_reg;                         //write data bus            | target
   reg  [TGA_WIDTH-1:0]                  itr_tga_reg;                         //address tags              |
   reg  [TGC_WIDTH-1:0]                  itr_tgc_reg;                         //bus cycle tags            |
   reg  [TGWD_WIDTH-1:0]                 itr_tgd_reg;                         //write data tags           +-



















   
   //Signal propagation to the target bus
   assign tgt_cyc_o        = itr_cyc_i;                                       //bus cycle indicator       +-
   assign tgt_stb_o        = itr_stb_i;                                       //access request            |
   assign tgt_we_o         = itr_we_i;                                        //write enable              |
   assign tgt_lock_o       = itr_lock_i;                                      //uninterruptable bus cycle | initiator
   assign tgt_sel_o        = itr_sel_i;                                       //write data selects        | to
   assign tgt_adr_o        = itr_adr_i;                                       //write data selects        | target
   assign tgt_dat_o        = itr_dat_i;                                       //write data bus            |
   assign tgt_tga_o        = itr_tga_i;                                       //address tags              |
   assign tgt_tgc_o        = itr_tgc_i;                                       //bus cycle tags            |
   assign tgt_tgd_o        = itr_tgd_i;                                       //write data tags           +-

   //Signal propagation to the initiator bus
   assign itr_ack_o        = tgt_ack_i;                                       //bus cycle acknowledge     +-
   assign itr_err_o        = tgt_err_i;                                       //error indicator           | target
   assign itr_rty_o        = tgt_rty_i;                                       //retry request             | to
   assign itr_stall_o      = tgt_stall_i;                                     //access delay              | initiator
   assign itr_dat_o        = tgt_dat_i;                                       //                          |
   assign itr_tgd_o        = tgt_tgd_i;                                       //read data tags            +-







   //Finite state machine
   parameter STATE_READY         = 2'b00;  //waiting for bus request (reset state)
   parameter STATE_REQ_CAPTURED  = 2'b10;  //initiator request captured(reset state)
   parameter STATE_RESP_PENDING  = 2'b01;  //waiting for bus acknowledge
   parameter STATE_RESP_CAPTURED = 2'b11;  //target response captured
   always @*
     begin
        //Default outputs
        state_next       = state_reg;                                         //remain in current state
	tgt_cyc_o        = itr_cyc_i;                                         //propagate bus cycle indicator     
	tgt_stb_o        = itr_stb_i;                                         //propagate access request          
	itr_stall_o      = tgt_stall_i;                                       //propagate access delay            
	case (state_reg)
	  STATE_NEW_REQ:
	    begin
	       tgt_cyc_o   = 1'b0;                                            //don't propagate bus cycle indicator    
	       tgt_stb_o   = 1'b0;                                            //don't propagate access request         
	       itr_stall_o = 1'b1;                                            //stall initiator
	       if (itr_cyc_i & itr_stb_i & ~tgt_stall_i)                      //bus request before initiator only clock event 
		 begin
		    state_next      = STATE_RESP_PENDING;                     //initiate target request
		 end
	    end
	  STATE_RESP_PENDING:
	    begin
	       if (




 
 // if (|REG_ITR)
	    else                                                              //registered requests
	      begin
		 if (itr2tgt_sync_i)                                          //concurrent clock event next
		   begin
		      if (itr_cyc_i & itr_stb_i & ~tgt_stall_i)               //bus request before initiator only clock event 
			state_next    = STATE_RESP_PENDING;                   //handle captured initiator request
		   end
		 else
		   begin
		      itr_stall_o     = 1'b1;                                 //stall initiator
		   end
	      end // else: !if(|REG_ITR)
	  STATE_REQ_CAPTURED:
	    if (|REG_ITR)                                                     //registered requests
	      begin
	       //tgt_cyc_o   = 1'b1;                                          //request target bus    
	       //tgt_stb_o   = 1'b1;                                          //         
		 if (itr2tgt_sync_i & ~tgt_stall_o)                           //bus request before concurrent clock event
		   state_next      = STATE_RESP_PENDING;                      //target asccess initiated
	      end
	    else
	      begin
		 state_next = STATE_READY;                                    //unreachable
	      end
	  STATE_RESP_PENDING:
	    if (|REG_TGT)                                                     //registered responses
	      begin							      
		 if (itr_ack_o | itr_err_o | itr_rty_o)			      
		   begin						      
		      state_next      = STATE_RESP_CAPTURED;                  //handle captured initiator request
		      capture_response = 1'b1;                                //capture target response	
		   end
	      end							      
	    else                                                              //unregistered responses
	      if (|REG_ITR)                                                   //registered requests
		begin							      
	           tgt_cyc_o   = 1'b0;                                        //don't propagate bus cycle indicator    
	           tgt_stb_o   = 1'b0;                                        //don't propagate access request         
		   itr_stall_o = 1'b1;                                        //stall initiator
		   if (~itr2tgt_sync_i &                                      //bus request before initiator only clock event
		       itr_cyc_i & itr_stb_i & ~tgt_stall_o) 
		     begin
			state_next      = STATE_REQ_CAPTURED;                 //handle captured initiator request
			capture_request = 1'b1;                               //capture initiator request
		     end						      
		   else							      
		     begin						      
			state_next      = STATE_READY;                        //bus is idle
		     end						      
		end // if (|REG_ITR)					      
	      else                                                            //registered requests
		begin							      
		   if (itr2tgt_sync_i)                                        //concurrent clock event next
		     begin						      
			if (itr_cyc_i & itr_stb_i & ~tgt_stall_i)             //bus request before initiator only clock event 
			  state_next    = STATE_RESP_PENDING;                 //wait for bus acknowledge
		     end
		   else
		     begin
			state_next      = STATE_READY;                        //bus is idle
			itr_stall_o     = 1'b1;                               //stall initiator
		     end
		end // else: !if(|REG_ITR)
	  STATE_RESP_CAPTURED:
	    if (|REG_TGT)                                                     //registered requests
	      if (|REG_ITR)                                                   //registered requests
		begin							      
	           tgt_cyc_o   = 1'b0;                                        //don't propagate bus cycle indicator    
	           tgt_stb_o   = 1'b0;                                        //don't propagate access request         
		   itr_stall_o = 1'b1;                                        //stall initiator
		   capture_response = 1'b1;                                   //capture target response	
		   if (~itr2tgt_sync_i &                                      //bus request before initiator only clock event
		       itr_cyc_i & itr_stb_i & ~tgt_stall_o) 
		     begin
			state_next      = STATE_REQ_CAPTURED;                 //handle captured initiator request
			capture_request = 1'b1;                               //capture initiator request
		     end						      
		   else							      
		     begin						      
			state_next      = STATE_READY;                        //bus is idle
		     end						      
		end // if (|REG_ITR)					      
	      else                                                            //registered requests
		begin							      
		   if (itr2tgt_sync_i)                                        //concurrent clock event next
		     begin						      
			if (itr_cyc_i & itr_stb_i & ~tgt_stall_o)             //bus request before initiator only clock event 
			  state_next    = STATE_RESP_PENDING;                 //wait for bus acknowledge
		     end
		   else
		     begin
			state_next      = STATE_READY;                        //bus is idle
			itr_stall_o     = 1'b1;                               //stall initiator
		     end
		end // else: !if(|REG_ITR)
	endcase // case (state_reg)
     end // always @ *

   //State variable
   always @(posedge async_rst_i or posedge itr_clk_i)
     if (async_rst_i)                                                         //asynchronous reset
       state_reg <= STATE_READY;				              
     else if (sync_rst_i)                                                     //synchronous reset
       state_reg <= STATE_READY;				              
     else if(1)							              
       state_reg <= state_next;                                               //state transition

   
endmodule // WbXbc_standardizer
