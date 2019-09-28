module StackProf
  module Formatter
    module D3Flamegraph
      def print_d3_flamegraph(f=STDOUT, skip_common=true)
        raise "profile does not include raw samples (add `raw: true` to collecting StackProf.run)" unless raw = data[:raw]

        stacks = []
        max_x = 0
        max_y = 0
        while len = raw.shift
          max_y = len if len > max_y
          stack = raw.slice!(0, len+1)
          stacks << stack
          max_x += stack.last
        end

        # d3-flame-grpah supports only alphabetical flamegraph
        stacks.sort!

        require "json"
        json = JSON.generate(convert_to_d3_flame_graph_format("<root>", stacks, 0), max_nesting: false)

        # This html code is almost copied from d3-flame-graph sample code.
        # (Apache License 2.0)
        # https://github.com/spiermar/d3-flame-graph/blob/gh-pages/index.html

        f.print <<-END
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
    <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/gh/spiermar/d3-flame-graph@2.0.3/dist/d3-flamegraph.css">

    <style>

    /* Space out content a bit */
    body {
      padding-top: 20px;
      padding-bottom: 20px;
    }

    /* Custom page header */
    .header {
      padding-bottom: 20px;
      padding-right: 15px;
      padding-left: 15px;
      border-bottom: 1px solid #e5e5e5;
    }

    /* Make the masthead heading the same height as the navigation */
    .header h3 {
      margin-top: 0;
      margin-bottom: 0;
      line-height: 40px;
    }

    /* Customize container */
    .container {
      max-width: 990px;
    }

    address {
      text-align: right;
    }
    </style>

    <title>stackprof (mode: #{ data[:mode] })</title>

    <!-- HTML5 shim and Respond.js for IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
      <script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
    <![endif]-->
  </head>
  <body>
    <div class="container">
      <div class="header clearfix">
        <nav>
          <div class="pull-right">
            <form class="form-inline" id="form">
              <a class="btn" href="javascript: resetZoom();">Reset zoom</a>
              <a class="btn" href="javascript: clear();">Clear</a>
              <div class="form-group">
                <input type="text" class="form-control" id="term">
              </div>
              <a class="btn btn-primary" href="javascript: search();">Search</a>
            </form>
          </div>
        </nav>
        <h3 class="text-muted">stackprof (mode: #{ data[:mode] })</h3>
      </div>
      <div id="chart">
      </div>
      <address>
        powered by <a href="https://github.com/spiermar/d3-flame-graph">d3-flame-graph</a>
      </address>
      <hr>
      <div id="details">
      </div>
    </div>

    <!-- D3.js -->
    <script src="https://d3js.org/d3.v4.min.js" charset="utf-8"></script>

    <!-- d3-tip -->
    <script type="text/javascript" src=https://cdnjs.cloudflare.com/ajax/libs/d3-tip/0.9.1/d3-tip.min.js></script>

    <!-- d3-flamegraph -->
    <script type="text/javascript" src="https://cdn.jsdelivr.net/gh/spiermar/d3-flame-graph@2.0.3/dist/d3-flamegraph.min.js"></script>

    <script type="text/javascript">
    var flameGraph = d3.flamegraph()
      .width(960)
      .cellHeight(18)
      .transitionDuration(750)
      .minFrameSize(5)
      .transitionEase(d3.easeCubic)
      .sort(true)
      //Example to sort in reverse order
      //.sort(function(a,b){ return d3.descending(a.name, b.name);})
      .title("")
      .onClick(onClick)
      .differential(false)
      .selfValue(false);


    // Example on how to use custom tooltips using d3-tip.
    // var tip = d3.tip()
    //   .direction("s")
    //   .offset([8, 0])
    //   .attr('class', 'd3-flame-graph-tip')
    //   .html(function(d) { return "name: " + d.data.name + ", value: " + d.data.value; });

    // flameGraph.tooltip(tip);

    var details = document.getElementById("details");
    flameGraph.setDetailsElement(details);

    // Example on how to use custom labels
    // var label = function(d) {
    //  return "name: " + d.name + ", value: " + d.value;
    // }
    // flameGraph.label(label);

    // Example of how to set fixed chart height
    // flameGraph.height(540);

    d3.select("#chart")
        .datum(#{ json })
        .call(flameGraph);

    document.getElementById("form").addEventListener("submit", function(event){
      event.preventDefault();
      search();
    });

    function search() {
      var term = document.getElementById("term").value;
      flameGraph.search(term);
    }

    function clear() {
      document.getElementById('term').value = '';
      flameGraph.clear();
    }

    function resetZoom() {
      flameGraph.resetZoom();
    }

    function onClick(d) {
      console.info("Clicked on " + d.data.name);
    }
    </script>
  </body>
</html>
        END
      end

      def convert_to_d3_flame_graph_format(name, stacks, depth)
        weight = 0
        children = []
        stacks.chunk do |stack|
          if depth == stack.length - 1
            :leaf
          else
            stack[depth]
          end
        end.each do |val, child_stacks|
          if val == :leaf
            child_stacks.each do |stack|
              weight += stack.last
            end
          else
            frame = frames[val]
            child_name = "#{ frame[:name] } : #{ frame[:file] }:#{ frame[:line] }"
            child_data = convert_to_d3_flame_graph_format(child_name, child_stacks, depth + 1)
            weight += child_data["value"]
            children << child_data
          end
        end

        {
          "name" => name,
          "value" => weight,
          "children" => children,
        }
      end
    end
  end
end
