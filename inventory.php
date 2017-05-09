<?php
error_reporting(E_ALL);
ini_set('display_errors', TRUE);
ini_set('display_startup_errors', TRUE);

session_start();

if ( !isset ( $_SESSION['user'] ) ) {
  header ( "location: index.php" );
}

$user = $_SESSION['user']; //assignes user value
$dbh = new PDO ( "mysql:host=localhost;dbname=id591640_rta", 'id591640_root', 'Ol3g@123' );

if ( isset ( $_POST['submit_update'] ) ) {

  $details = ( $_POST['details'] );
  $posted= strftime ( "%Y-%m-%e %X" );
  $public = "no";

  try {
    $dbh = new PDO ( "mysql:host=localhost;dbname=Storm", 'root', 'root' );

    if ( isset ( $_POST['public'] ) ) {
      $public = "yes";
    }

    $sql = ( "INSERT INTO `list` (`details`, `posted`, `public` ) VALUES ( :details, :posted, :public  )" );
    $stmt = $dbh->prepare( $sql );

    $stmt->bindParam( ':details', $details );
    $stmt->bindParam( ':posted', $posted );
    $stmt->bindParam( ':public', $public );

    if ( $stmt->execute() ) {
      header ( "location: home.php" );
    } else {
      print "Unable to add new item<br/>";
    }
  } catch ( PDOException $e ) {
    logger ( "[insert_record] Unable to insert new record ->  ");
  }
}

try {
  $list_data = $dbh->query( "SELECT * FROM `list`" )->fetchAll();
} catch ( PDOException $e ) {
  logger ( "Unable to execute query", 2 );
}

?>

<html>
<head>
  <title>Inventory</title>
  <!-- Navigation Bar Template -->
  <?php require_once'include/navbar.php'; ?>

  <!-- CSS -->
  <link rel="stylesheet" href="include/inventory.css">

</head>
<body>

<div class="container-fluid">
  <div class="row">
    <div class="col-md-4">
      <div class="panel panel-primary">
        <div class="panel-heading">Update</div>
        <div class="panel-body">
          <form class="form-horizontal" method="POST" action="home.php">
            <div class="form-group comment-input">
              <label for="comment">Data:</label>
              <textarea class="form-control text" rows="5" name="details"></textarea>
            </div>
            <div class="form-group comment-input">
              <label><input type="checkbox" name="public" value="yes"> Public</label>
              <button type="submit" class="btn btn-primary btn-sm pull-right" value="" name="submit_update">Submit</button>
            </div>
          </form>
        </div>
        <div class="panel-footer"></div>
      </div>
    </div>
  </div>
</div>
<div class="contain-list container-fluid">
  <div class="row">
    <div class="col-xs-12 col-sm-12 col-md-12">
      <div class="panel panel-default">
        <div class="panel-heading">Comments</div>
        <table class="table table-responsive table-striped table-hover table-condensed">
          <thead>
            <tr>
              <th class="col-xs-1 text-center"><span class="glyphicon glyphicon-th-list"></span></th>
              <th class="col-xs-3">Details</th>
              <th class="col-xs-3 text-center">Posted</th>
              <th class="col-xs-2 text-center">Edited</th>
              <th class="col-xs-1 text-center"><span class="glyphicon glyphicon-edit"></span></th>
              <th class="col-xs-1 text-center">Delete</th>
              <th class="col-sx-1 text-center">Public</th>
            </tr>
          </thead>
          <?php
            if ( !empty ( $list_data ) ) {
              foreach ( $list_data as $row ) {
                print "<tbody>";
                  print "<tr>";
                    print '<td class="col-xs-1 text-center">' . $row['id'] . "</td>";
                    print '<td class="col-xs-3">' . $row['details'] . "</td>";
                    print '<td class="col-xs-3 text-center">' . $row['posted'] . "</td>";
                    print '<td class="col-xs-2 text-center">' . $row['edited'] . "</td>";
                    print '<td class="col-xs-1 text-center"><a href="edit.php?id=' . $row['id'] . '"><span class="glyphicon glyphicon-pencil"></span></a> </td>';
                    print '<td class="col-xs-1 text-center"><a href="delete.php?id=' . $row['id'] . '"><span class="glyphicon glyphicon-trash"></span></a> </td>';
                    if ( $row['public'] == "yes" ) {
                      print '<td class="col-xs-1 text-center"><span class="glyphicon glyphicon-ok"></span></td>';
                    } else {
                      print '<td class="col-xs-1 text-center"> </td>';
                    }
                  print "</tr>";
                print "</tbody>";
              }
            } else {
              print "<tbody>";
                print "<tr>";
                  print '<td class="col-xs-1 text-center"></td>';
                  print '<td class="col-xs-3">No data available at this time</td>';
                  print '<td class="col-xs-3 text-center"></td>';
                  print '<td class="col-xs-2 text-center"></td>';
                  print '<td class="col-xs-1 text-center"></span></a> </td>';
                  print '<td class="col-xs-1 text-center"></span></a> </td>';
                  print '<td class="col-xs-1 text-center"></td>';
                print "</tr>";
              print "</tbody>";
            }
          ?>
        </table>
      </div>
    </div>
  </div>
</div>

</body>

</html>
