<?php

error_reporting(E_ALL);
ini_set('display_errors', TRUE);
ini_set('display_startup_errors', TRUE);

// Load Class File
require_once 'include/util_class.php';

// Instantiate Class file handles
$logger = new Logger();
$dbh    = new DB();

session_start();

  if ( ! isset ( $_SESSION['user'] ) ) {
    header ( "location: index.php" );
  }

  $user = $_SESSION['user']; //assignes user value
  date_default_timezone_set('America/New_York');

  // RETRIEVE THE CURRENT USERS AUTHORIZATION LEVEL TO SEE WHAT WE CAN SHOW THEM

  try {
    $query = "SELECT * FROM `users` ORDER BY `auth_level`";
    $current_users = $dbh->connect_db()->query( $query )->fetchAll();
    foreach ( $current_users as $row ) {
      if ( $row['username'] == $user ) {
        $_SESSION['auth_level'] = $row['auth_level'];
        $_SESSION['user_id'] = $row['id'];
        $user_id = $_SESSION['user_id'];
      }
    }
  } catch ( PDOException $e ) {
    $logger->log_message ( "Unable to execute query to determine user authentication level -> {$query}", 3, "user" );
  }

  // SUM FOR EXPENSE DETAILS PANEL TABLE

  try {
 
    // USER ONLY -> Query to retrieve sum of the total expenses recorded for the info panels
    $running_query = "SELECT SUM(amount) FROM `expense` WHERE `user_id` = $user_id";
    // USER ONLY -> Execute query or log an entry with failure
    $running_expense_query = $dbh->connect_db()->query ( $running_query ) or $logger->log_message ( "Unable to retrieve running_query -> {$running_query}", 3, "expense" );

    // If the query is successful
    if ( $running_expense_query ) {
      // FETCH THE COLUMN SUM OF THE QUERY
      $total = $running_expense_query->fetchColumn();
      // ROUND THE TOTAL AMOUNT TO 2 DECIMAL PLACES
      $total_running_expense = round ( $total, 2 );

    } else {
      $running_expense_query = "N/A";
    }

    // USER ONLY -> Query to retrieve current expenses to display in home dashboard
    $current_expense_query = "SELECT * FROM `expense` WHERE `user_id` = $user_id AND `deleted` = 'f' ORDER BY `timestamp` DESC LIMIT 15";
    // USER ONLY -> Execute the query or log an entry with failure
    $current_expense = $dbh->connect_db()->query ( $current_expense_query )->fetchAll() or $logger->log_message ( "Unable to retrieve current_expense -> {$current_expense_query}", 3, "expense" );

  } catch ( PDOException $e ) {
    $logger->log_message ( "Error encountered" . $e->getMessage(), 3, "expense" );
  }

  // PUNCHARD SYSTEM FUNCTIONALITY

  if ( isset ( $_POST[ 'punch' ] ) ) {
    $recent_punch = $dbh->connect_db()->query( "SELECT max(`DateTime`) FROM timecard WHERE `user_id` = {$user_id}" )->fetchColumn();

    if ( $recent_punch ) {
      // Determine if our current max time_in has a punch out value or not
      $punch_type = $dbh->connect_db()->query ( "SELECT `type` FROM `timecard` WHERE `DateTime` = '$recent_punch' AND `user_id` = '$user_id'" )->fetchColumn();

      // If we are still currently punched in, then update the time_out value with the new punch
      if ( $punch_type == 'in' ) {
        $sql = $dbh->connect_db()->prepare( "UPDATE `timecard` SET `time_out` = now(), `DateTime` = now(), `type` = 'out' WHERE `DateTime` = '$recent_punch' AND `user_id` = {$user_id}" );
        if ( $sql->execute( ) ) {
          header ( "location: home.php" );
        } else {
          $logger->log_message ( "Unable to update punch in", 3, "timecard" );
        }
      // If we are punched out, then record a new punch with in
      } elseif ( $punch_type == 'out' ) {
        $sql = $dbh->connect_db()->prepare( "INSERT INTO `timecard` SET `user_id` = $user_id, `time_in` = now(), `DateTime` = now(), `type` = 'in'" );
        if ( $sql->execute() ) {
          header ( "location: home.php" );
        } else {
          $logger->log_message ( "Unable to insert new punch", 3, "timecard" );
        }
      }
    } else {
      $sql = $dbh->connect_db()->prepare( "INSERT INTO `timecard` SET `user_id` = $user_id, `time_in` = now(), `DateTime` = now(), `type` = 'in'" );
     
      if ( $sql->execute() ) {
        header ( "location: home.php" );
      } else {
        $logger->log_message ( "Unable to insert new punch", 3, "timecard" );
      }
    }
  }

    // RETRIEVE THE CURRENT USERS DAYS WORKED FROM TIMECARD
    try {
      $recent_punch = $dbh->connect_db()->query( "SELECT max(`DateTime`) FROM timecard WHERE `user_id` = '$user_id'" )->fetchColumn();
      $punch_type = $dbh->connect_db()->query( "SELECT `type` FROM `timecard` WHERE `DateTime` = '$recent_punch' AND `user_id` = '$user_id'" )->fetchColumn();

      if ( $punch_type == 'in' ) {
        // Query for the most recent punch in that we have for the user
        $recent_in = "SELECT `time_in` FROM `timecard` WHERE `type` = 'in' AND `user_id` = $user_id";
        // Execute query or log failure
        $punch_in_timestamp = date ( 'm-d-Y', strtotime ( $dbh->connect_db()->query( $recent_in )->fetchColumn() ) ) or $logger->log_message ( "Unable to retrieve data for query -> {$recent_in}", 3, 'timecard' );

      } elseif ( $punch_type == 'out' ) {
        $query = "SELECT SUM( DATEDIFF ( `time_out`, `time_in` ) ) as DateDiff FROM `timecard` WHERE `user_id` = $user_id";
        $running_days_worked = $dbh->connect_db()->query( $query )->fetchColumn();
      }
    } catch ( PDOException $e ) {
      print ( "Error -> " . $e->getMessage() );
    }


  // RECEIPT INPUT FORM AND VALIDATION

    // Load Expense category input fields
    $category_query = "SELECT * FROM `expense_category`";
    $categories = $dbh->connect_db()->query( $category_query )->fetchAll();

  if ( isset ( $_POST['submit-receipt'] ) ) {
    $expense_name     = $_POST['expense-name'];
    $expense_amount   = $_POST['expense-amount'];
    $expense_category = $_POST['expense-category'];

    if ( $_FILES[ 'expense-image' ][ 'size' ] != 0 && $_FILES[ 'expense-image' ][ 'error' ] == 0 ) {
      $upload_dir = "images/";

      if ( isset ( $expense_name ) && !empty ( $expense_name ) ) {
        $file_name    = explode( ".", $_FILES[ 'expense-image' ][ 'name' ] );
        $new_filename = $expense_name . '.' . round( microtime ( true ) ) . '.' . end ( $file_name );
        $target_path  = $upload_dir . $new_filename;
      } else {
        $file_name    = explode( ".", $_FILES[ 'expense-image' ][ 'name' ] );
        $new_filename = round( microtime (true) ) . '.' . end( $file_name );
        $target_path  = $upload_dir . $new_filename;
      }

      if ( move_uploaded_file( $_FILES[ 'expense-image' ][ 'tmp_name' ] , $target_path ) ) {
        $sql = $dbh->connect_db()->prepare( "INSERT INTO `expense` SET `expense_name` = :expense_name, `amount` = :amount, `user_id` = :user_id, `category` = :category, `image_dest` = :image_upload, `deleted` = 'f' ");
        $sql->bindParam( ':expense_name', $expense_name );
        $sql->bindParam( ':amount', $expense_amount );
        $sql->bindParam( ':user_id', $_SESSION['user_id'] );
        $sql->bindParam( ':category', $expense_category );
        $sql->bindParam( ':image_upload', $target_path );

        if ( $sql->execute() ) {
          header ( "location: home.php" );
        } else {
          $logger->log_message ( "Unable to insert new expense -> User: {$_SESSION['user']} -> Query: {$sql}", 3, "expense" );
        }
      } else {
        $logger->log_message ( "There was an error with the uploading the file: $target_path<br/>", 3, "expense" );
      }
    } else {

      $sql = $dbh->connect_db()->prepare( "INSERT INTO `expense` SET `expense_name` = :expense_name, `amount` = :amount, `user_id` = :user_id, `category` = :category, `deleted` = 'f' ");
      $sql->bindParam( ':expense_name', $expense_name );
      $sql->bindParam( ':amount', $expense_amount );
      $sql->bindParam( ':user_id', $_SESSION['user_id'] );
      $sql->bindParam( ':category', $expense_category );
      
      if ( $sql->execute() ) {
        header ( "location: home.php" );
      } else {
        $logger->log_message ( "Unable to insert new expense -> User: {$_SESSION['user']} -> Query: {$sql}", 3, "expense" );
      }
    }
  }

  if ( isset ( $error ) ) {
    foreach ( $error as $err ) {
      print "Error: $err<br/>";
    }
  }
?>

<html>
  <head>
    <title>K-Brothers</title>
    <!-- Navigation Bar Template -->
    <?php require_once'include/navbar.php'; ?>

    <!-- VIEWPORT FOR MOBILE DEVICES -->
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- CSS -->
    <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.1.1/jquery.min.js"></script>
    <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
    
    <!-- CUSTOM CSS STYLESHEET -->
    <link rel="stylesheet" href="include/home.css">

  </head>

<script type="text/javascript">

$(document).on('click', '.panel-heading span.clickable', function(e){
  var $this = $(this);
if(!$this.hasClass('panel-collapsed')) {
  $this.parents('.panel').find('.panel-body').slideUp('slow');
  $this.addClass('panel-collapsed');
  $this.find('i').removeClass('glyphicon-chevron-up').addClass('glyphicon-chevron-down');
} else {
  $this.parents('.panel').find('.panel-body').slideDown();
  $this.removeClass('panel-collapsed');
  $this.find('i').removeClass('glyphicon-chevron-down').addClass('glyphicon-chevron-up');
}
})

</script>


<body>
  <div class="container-fluid">
    <div class="row">
      <div class="col-xs-6 col-sm-3 col-md-2">
        <div class="msg msg-info">
          <div class="text-center"><h5>Expenses</h5></div>
          <hr>
          <div class="text-center">
            <h4>$ 
              <?php 
                if ( isset ( $total_running_expense ) ) { 
                  print number_format( $total_running_expense, 2, '.', ',' ); 
                } else {
                  print "0.00";
                }
              ?></h4>
          </div>
        </div>
      </div>
      <div class="col-xs-6 col-sm-3 col-md-2">
        <div class="msg msg-danger">
          <div class="text-center">
            <h5>Punchcard</h5>
          </div>
          <hr>
          <?php
            if ( isset ( $punch_type ) ) {
              if ( $punch_type == 'out' ) {
                print '<div class="text-center">
                        <form class="form form-punch" action="home.php" method="post">
                          <button class="btn btn-success btn-submit" name="punch">Clock In</button>
                        </form>
                      </div>';
              } elseif ( $punch_type == 'in' ) {
                print '<div class="text-center">
                        <form class="form form-punch" action="home.php" method="post">
                          <button class="btn btn-danger btn-submit" name="punch">Clock Out</button>
                        </form>
                      </div>';
              } else {
                print '<div class="text-center">
                          <form class="form form-punch" action="home.php" method="post">
                            <button class="btn btn-success btn-submit" name="punch">Clock In</button>
                          </form>
                        </div>';
              }
            }
           ?>
      </div>
    </div>
      <?php if ( isset ( $format_in ) && !empty ( $format_in ) ) {
        print '<div class="col-xs-12 col-sm-3 col-md-2">
          <div class="msg msg-info">
            <div class="text-center">
              <h5>Punchcard</h5>
            </div>
            <hr>
            <div class="text-left">
              <label>In: ' . $format_in . '</label><br/>
              <label>Out:</label>
            </div>
        </div>
      </div>';
      } ?>
    <div class="col-xs-6 col-sm-3 col-md-2">
      <div class="msg msg-info">
        <div class="text-center"><h5>Days Worked</h5></div>
        <hr>
        <div class="text-center">
          <h4>
            <?php 
              if ( isset ( $running_days_worked ) ) { 
                print $running_days_worked; 
              } else {
                print "En-route";
              }
            ?></h4>
        </div>
      </div>
    </div>
    <div class="col-xs-6 col-sm-3 col-md-2">
        <div class="msg msg-info">
          <div class="text-center"><h5>Clock Detail</h5></div>
          <hr>
          <div class="text-center">
            <h4>
              <?php 
                if ( isset ( $punch_in_timestamp ) ) {
                  print $punch_in_timestamp;
                } else {
                  print "Clocked Out";
                }
              ?></h4>
          </div>
        </div>
      </div>
    </div>
  </div>
  <div class="container-fluid">
    <div class="row">
      <div class="col-xs-12 col-sm-12 col-md-6 col-lg-6">
        <div class="panel panel-primary">
          <div class="panel-heading">
            <h3 class="panel-title">Receipt Tracking</h3>
            <span class="pull-right clickable"><i class="glyphicon glyphicon-chevron-up"></i></span>
          </div>
          <div class="panel-body">         
            <form class=" form-horizontal" action="home.php" method="post" enctype="multipart/form-data">
              <div class="form-group">
                <div class="col-md-6">
                  <label for="expense-name">Expense</label>
                  <input type="text" class="form-control" name="expense-name" placeholder="Best Buy">
                  <small id=expense-help class="form-text text-muted">Name of establishment for expense</small> 
                </div>
                <div class="col-md-6">
                  <label for="expense-category">Category</label>
                  <select class="form-control" name="expense-category">
                      <option>Please select one</option>
                      <?php
                        if ( isset ( $categories ) && !empty ( $categories ) ) {
                          foreach ( $categories as $cat ) {
                            print '<option>' . $cat['category'] . '</option>';
                          }
                        }
                      ?>
                  </select>
                  <small id="expense-help" class="form-text text-muted">Category for spenditure</small>
                </div>
              </div>
                <div class="form-group">
                  <div class="col-xs-4 col-md-6">
                    <label for="expense-image">Upload</label><br/>
                    <label class="btn btn-primary btn-file">Browse <input type="file" name="expense-image" style="display: none;"></label><br/>
                    <small id="expense-help" class="form-text text-muted">Receipt Image</small>
                  </div>
                  <div class="col-xs-6 col-sm-4 col-md-4 pull-right">
                    <div class="input-group">
                    <span class="input-group-addon">$</span>
                    <input type="float" class="form-control" name="expense-amount" placeholder="100.00">
                    </div>
                    <small id="expense-help" class="form-text text-muted">Amount spent</small>
                  </div>
                </div>
              <hr/>
              <button class="btn btn-primary btn-submit pull-right" name="submit-receipt">Submit</button>
            </form>
          </div>
        </div>
      </div>
      <div class="col-xs-12 col-sm-12 col-md-6 col-lg-6">
        <div class="panel panel-info">
          <div class="panel-heading">
            <div class="panel-title">Expense Details</div>
            <span class="pull-right clickable"><i class="glyphicon glyphicon-chevron-up"></i></span>
            <span class=""><i class="glyphicon glyphicon-filter"></i></span>
          </div>
          <div class="panel-body expense-panel">
            <table class="table expense-table table-responsive table-hover">
              <thead>
                <tr>
                  <th class="col-xs-1 col-sm-2 col-md-2 col-lg-2 text-center"><span class="glyphicon glyphicon-pencil"></span></th>
                  <th class="col-xs-2 col-sm-2 col-md-3 col-lg-3 text-center">Date</th>  
                  <th class="col-xs-3 col-sm-3 col-md-3 col-lg-3 text-left">Category</th>
                  <th class="col-xs-2 col-sm-2 col-md-2 col-lg-2 text-center" ><i class="fa fa-picture-o"></i></th>
                  <th class="col-xs-3 col-sm-3 col-md-3 col-lg-3 text-left">Amount</th>
                </tr>
              </thead>
              <?php
                if ( !empty ( $current_expense ) ) {
                  foreach ( $current_expense as $row ) {
                    print "<tbody>";
                      print "<tr>";
                        print '<td class="col-xs-1 col-sm-2 col-md-2 col-lg-2 text-center"><a href="delete_expense.php?id=' . $row['id'] . '"><i class="fa fa-trash"></i></a></td>';
                        print '<td class="col-xs-3 col-sm-3 col-md-3 col-lg-3 text-center">' . date ('m-d', strtotime( $row['timestamp'] ) ) . '</td>';
                        print '<td class="col-xs-3 col-sm-3 col-md-3 col-lg-3 text-left">' . $row['category'] . '</td>';
                        if ( isset ( $row['image_dest'] ) && !empty ( $row['image_dest'] ) ) {
                          print '<td class="col-xs-2 col-sm-2 col-md-2 col-lg-2 text-center"><a href="' . $row[ 'image_dest' ] . '"><i class="fa fa-picture-o"></i></a></td>';
                        } else {
                          print '<td class="col-xs-2 text-center"></td>';
                        }
                        print '<td class="col-xs-3 col-sm-3 col-md-3 col-lg-3 text-left"><i class="fa fa-usd"></i> ' . number_format( $row['amount'], 2, '.', ',' ) . '</td>';
                      print "</tr>";
                    print "</tbody>";
                  }
                } else {
                  print "<tbody>";
                    print "<tr>";
                      print '<td class="col-xs-1 text-center"></td>';
                      print '<td class="col-xs-3 text-center"></td>';
                      print '<td class="col-xs-5 ">No data available</td>';
                      print '<td class="col-xs-2 text-center"></td>';
                      print '<td class="col-xs-2 text-center"></td>';
                    print "</tr>";
                  print "</tbody>";
                }
              ?>
            </table>
          </div>
        </div>
      </div>
    </div>
  </div>
  <div class="container-fluid">
    <div class="row">
      <div class="col-xs-12 col-sm-12 col-md-6">
        <?php if ( $_SESSION['auth_level'] == "admin" ) { ?>
          <div class="panel panel-success">
            <div class="panel-heading">
              <h3 class="panel-title">Current Registered Users</h3>
              <span class="pull-right clickable"><i class="glyphicon glyphicon-chevron-up"></i></span>
            </div>
            <div class="panel-body user-panel">
              <table class="table table-user table-responsive table-striped table-hover table-condensed">
                <thead>
                  <tr>
                    <th class="col-xs-1 text-center"><span class="glyphicon glyphicon-th-list"></span></th>
                    <th class="col-xs-5">Username</th>
                    <th class="col-xs-2 text-center">Auth Level</th>
                    <th class="col-xs-1 text-center">Delete</th>
                  </tr>
                </thead>
                <?php
                  if ( !empty ( $current_users ) ) {
                    foreach ( $current_users as $row ) {
                      print "<tbody>";
                        print "<tr>";
                          print '<td class="col-xs-1 text-center">' . $row['id'] . '</td>';
                          print '<td class="col-xs-5">' . $row['username'] . '</td>';
                          if ( $row['auth_level'] == "admin" ) {
                            print '<td class="col-xs-3 text-center"><span class="label label-success">Admin</span></td>';
                          } else {
                            print '<td class="col-xs-3 text-center"><span class="label label-info">Standard</span></td>';
                          }
                          print '<td class="col-xs-1 text-center"><a href="delete_user.php?id=' . $row['id'] . '"><span class="glyphicon glyphicon-trash"></span></a> </td>';
                        print "</tr>";
                      print "</tbody>";
                    }
                  } else {
                    print "<tbody>";
                      print "<tr>";
                        print '<td class="col-xs-1 text-center"></td>';
                        print '<td class="col-xs-5">No data available at this time</td>';
                        print '<td class="col-xs-3 text-center"></td>';
                        print '<td class="col-xs-1 text-center"></td>';
                      print "</tr>";
                    print "</tbody>";
                  }
                ?>
              </table>
            </div>
            <div class="panel-footer">Current Access Level: <?php print $_SESSION['auth_level'];?></div>
          </div>
        <?php } ?>
      </div>
    </div>
  </div>
</body>

</html>
