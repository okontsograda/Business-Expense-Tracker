<?php

  session_start();

	error_reporting(E_ALL);
	ini_set('display_errors', TRUE);
	ini_set('display_startup_errors', TRUE);

	// Load Class file
	require_once 'include/util_class.php';

	// Instantiate Class file handles
	$logger				=	new Logger();
	$report_class = new Reports();
  $dbh          = new DB();

  if ( ! isset ( $_SESSION['user'] ) ) {
  	$logger->log_message ( "[redirect] Access attempted to reports.php without login -> redirecting to login", 2, "user_login" );
    header ( "location: index.php" );
  }

  // Assign username value
  $user = $_SESSION['user'];
  // Query user_id value based on username from session
  $user_id_query = "SELECT `id` FROM `users` WHERE `username` = '$user' ";
  $user_id = $dbh->connect_db()->query ( $user_id_query )->fetchColumn();

  date_default_timezone_set('America/New_York');

  // LOAD FILTER OPTION DATA

  $category_query = "SELECT * FROM `expense_category`";
  $categories = $dbh->connect_db()->query( $category_query )->fetchAll();


  // LOGIC TO UPDATE REPORT FROM FILTER

  if ( isset ( $_POST['filter-update'] ) ) {
    $category = $_POST['category'];

    $filter_query = "SELECT * FROM `expense` WHERE `category` = '$category' AND `user_id` = '$user_id' ";
    $filter_result = $dbh->connect_db()->query( $filter_query )->fetchAll();

    $sum_query = "SELECT sum(amount) FROM `expense` WHERE `category` = '$category' AND `user_id` = '$user_id'";
    $sum_filter = $dbh->connect_db()->query ( $sum_query )->fetchColumn();

  }
?>

<!DOCTYPE html>
<html>
<head>
	
	<title>Reports</title>

    <!-- Navigation Bar Template -->
    <?php require_once'include/navbar.php'; ?>

    <!-- VIEWPORT FOR MOBILE DEVICES -->
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- BOOTSTRAP, JS, JQUERY, CSS -->
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
    <link rel="stylesheet" href="include/reports.css">


	<script>

	$(document).ready(function() {
	    $("div.bhoechie-tab-menu>div.list-group>a").click(function(e) {
	        e.preventDefault();
	        $(this).siblings('a.active').removeClass("active");
	        $(this).addClass("active");
	        var index = $(this).index();
	        $("div.bhoechie-tab>div.bhoechie-tab-content").removeClass("active");
	        $("div.bhoechie-tab>div.bhoechie-tab-content").eq(index).addClass("active");
	    });
	});

	</script>

</head>
<body>

<div class="container-fluid">
  <div class="row">
  	<div class="col-xs-12 col-sm-6 col-md-4 col-lg-4">
            <div class="panel panel-primary">
                <div class="panel-heading">
                    <h3 class="panel-title">Reports</h3>
                    <span class="pull-right">
                        <!-- Tabs -->
                        <ul class="nav panel-tabs">
                            <li class="active"><a href="#tab1" data-toggle="tab">Expense</a></li>
                            <li><a href="#tab2" data-toggle="tab">Timecard</a></li>
                        </ul>
                    </span>
                </div>
                <div class="panel-body">
                    <div class="tab-content">
                        <div class="tab-pane active" id="tab1">
                          <form action="reports.php" method="post">
                            <div class="container-fluid">
                              <div class="row" style="padding-bottom: 15px;">
                                <div class="col-md-5">
                                  <label>Category:</label>
                                  <select class="form-control" name="category" placeholder="Select one">
                                    <?php 
                                      foreach ( $categories as $cat ) {
                                        print '
                                          <option>' . $cat['category'] .'</option>';
                                      }
                                    ?>
                                  </select>
                                </div>
                              </div>
                              <div class="row">
                                <button class="btn btn-primary btn-submit pull-right" type="submit" name="filter-update">Update</button>
                              </div>
                            </div>
                          </form>
                        </div>
                        <div class="tab-pane" id="tab2">
                        	Timecard Params
                        </div>
                    </div>
                </div>
            </div>
    </div>
    <div class="col-xs-12 col-sm-6 col-md-8 col-lg-8">
      <div class="panel panel-primary">
        <!-- Default panel contents -->
        <div class="panel-heading">
            <h3 class="panel-title">Accounts and transactions report</h3>
        </div>
        <div class="panel-body">
        	<div class="col-xs-6 col-sm-6 col-md-6 col-lg-6">
          	<div style="font-size: 14px; font-weight: bold; text-decoration: underline;">Filter Params</div>
          	<div style="font-size: 13px; font-style: italic;"><?php if ( isset ( $category ) ) { print "Category: {$category}"; } ?></div>
            <div style="font-size: 13px; font-style: italic;"><?php if ( isset ( $sum_filter ) ) { print "Sum: $" . number_format($sum_filter, 2, '.', ',' ); } ?></div>
        	</div>
        	<div class="col-xs-6 col-sm-6 col-md-6 col-lg-6">
        		<div style="font-weight: 900;"></div>
        	</div>
        </div>
        <ul class="list-group list-table">  
          <li class="list-group-item">
            <table class="table table-report table-hover table-condensed table-striped">
                <thead>
                  <tr>
                    <th>Date</th>
                    <th>Category</th>
                    <th>Expense Name</th>
                    <th>Amount</th>
                  </tr>
                </thead>
                <tbody>
                  <?php
                    if ( isset ( $filter_result ) && !empty ( $filter_result ) ) {
                      foreach ( $filter_result as $res ) {
                      print '
                        <tr>
                          <td>' . date( 'm/d/Y', strtotime( $res[ 'timestamp' ] ) ) . '</td>
                          <td>' . $res[ 'category' ] . '</td>
                          <td>' . $res[ 'expense_name' ] . '</td>
                          <td>' . number_format( $res[ 'amount' ], 2, '.', ',' ) . '</td>
                        </tr>
                      ';
                      }
                    }
                  ?>  
                </tbody>
            </table>
          </li>
        </ul>
      </div>
    </div>
  </div>
</div>

</body>
</html>