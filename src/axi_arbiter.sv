// Copyright (c) 2018 ETH Zurich, University of Bologna
// All rights reserved.
//
// This code is under development and not yet released to the public.
// Until it is released, the code is under the copyright of ETH Zurich and
// the University of Bologna, and may contain confidential and/or unpublished
// work. Any reuse/redistribution is strictly forbidden without written
// permission from ETH Zurich.
//
// Bug fixes and contributions will eventually be released under the
// SolderPad open hardware license in the context of the PULP platform
// (http://www.pulp-platform.org), under the copyright of ETH Zurich and the
// University of Bologna.
//
// Fabian Schuiki <fschuiki@iis.ee.ethz.ch>


/// A round-robin arbiter.
module axi_arbiter (
  input logic clk_i       ,
  input logic rst_ni      ,
  AXI_ARBITRATION.arb arb
);

  logic [$clog2($bits(arb.in_req))-1:0] count_d, count_q;

  axi_arbiter_tree #(.NUM_REQ($bits(arb.in_req)), .ID_WIDTH(0)) i_tree (
    .in_req_i  ( arb.in_req  ),
    .in_ack_o  ( arb.in_ack  ),
    .in_id_i   ( '0          ),
    .out_req_o ( arb.out_req ),
    .out_ack_i ( arb.out_ack ),
    .out_id_o  ( arb.out_sel ),
    .shift_i   ( count_q     )
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      count_q <= 0;
    end else if (arb.out_req && arb.out_ack) begin
      count_q <= (count_d == $bits(arb.in_req) ? 0 : count_d);
    end
  end

  assign count_d = count_q + 1;

endmodule


/// An arbitration tree.
module axi_arbiter_tree #(
  /// The number of requestors.
  parameter int NUM_REQ = -1,
  /// The width of the ID on the requestor side.
  parameter int ID_WIDTH = -1
)(
  input  logic [NUM_REQ-1:0]                  in_req_i  ,
  output logic [NUM_REQ-1:0]                  in_ack_o  ,
  input  logic [NUM_REQ-1:0][ID_WIDTH-1:0]    in_id_i   ,
  output logic                                out_req_o ,
  input  logic                                out_ack_i ,
  output logic [ID_WIDTH+$clog2(NUM_REQ)-1:0] out_id_o  ,
  input  logic [$clog2(NUM_REQ)-1:0]          shift_i
);

  `ifndef SYNTHESIS
  initial begin
    assert(NUM_REQ  >= 0);
    assert(ID_WIDTH >= 0);
  end
  `endif

  // Calculate the number of requests after the head multiplexers. This is equal
  // to ceil(NUM_REQ/2).
  localparam NUM_INNER_REQ = (NUM_REQ+1)/2;

  // Extract the bit that we use for shifting the priorities in the head.
  logic shift_bit;
  assign shift_bit = shift_i[$high(shift_i)];

  // Perform pairwise arbitration on the head.
  logic [NUM_INNER_REQ-1:0] inner_req, inner_ack;
  logic [NUM_INNER_REQ-1:0][ID_WIDTH:0] inner_id;

  for (genvar i = 0; i < NUM_INNER_REQ; i++) begin : g_head
    localparam iA = i*2;
    localparam iB = i*2+1;
    if (iB < NUM_REQ) begin

      // Decide who wins arbitration. If both A and B issue a request, shift_bit
      // is used as a tie breaker. Otherwise we simply grant the request.
      logic sel;
      always_comb begin
        if (in_req_i[iA] && in_req_i[iB])
          sel = shift_bit;
        else if (in_req_i[iA])
          sel = 0;
        else if (in_req_i[iB])
          sel = 1;
        else
          sel = 0;
      end

      assign inner_req[i] = in_req_i[iA] | in_req_i[iB];
      assign in_ack_o[iA] = inner_ack[i] && (sel == 0);
      assign in_ack_o[iB] = inner_ack[i] && (sel == 1);
      assign inner_id[i]  = (sel ? in_id_i[iB] : in_id_i[iA]) << 1 | sel;
    end else begin
      assign inner_req[i] = in_req_i[iA];
      assign in_ack_o[iA] = inner_ack[i];
      assign inner_id[i]  = in_id_i[iA] << 1 | 0;
    end
  end

  // Instantiate the tail of the tree.
  if (NUM_INNER_REQ > 1) begin : g_tail
    axi_arbiter_tree #(
      .NUM_REQ  ( NUM_INNER_REQ ),
      .ID_WIDTH ( ID_WIDTH+1    )
    ) i_tail (
      .in_req_i  ( inner_req                   ),
      .in_ack_o  ( inner_ack                   ),
      .in_id_i   ( inner_id                    ),
      .out_req_o ( out_req_o                   ),
      .out_ack_i ( out_ack_i                   ),
      .out_id_o  ( out_id_o                    ),
      .shift_i   ( shift_i[$high(shift_i)-1:0] )
    );
  end else if (NUM_INNER_REQ == 1) begin : g_tail
    assign out_req_o = inner_req;
    assign inner_ack = out_ack_i;
    assign out_id_o  = inner_id[0];
  end else begin : g_tail
    assign out_req_o = '0;
    assign out_id_o  = '0;
  end

endmodule
