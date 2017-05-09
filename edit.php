<?php
error_reporting(E_ALL);
ini_set('display_errors', TRUE);
ini_set('display_startup_errors', TRUE);

session_start();
if ( isset ( $_SESSION['user'] ) ) {

} else {
  header ( "location: index.php" );
}

$user = $_SESSION['user'];
$id_exists = false;
$dbh = new PDO( "mysql:host=localhost;dbname=Storm", 'root', 'root' );

try {
  if ( isset ( $_POST['update'] ) ) {
    $id = $_SESSION['id'];
    $details = ( $_POST['details'] );
    $public = "no";
    $edited = strftime( "%Y-%m-%e %X" );

    if ( isset ( $_POST['public'] ) && ( $_POST['public'] != null ) ) {
      $public = "yes";
    }

    $sql = ( "UPDATE `list` SET `details` = :details, `public` = :public, `edited` = :edited  WHERE `id` = :id" );
    $stmt = $dbh->prepare( $sql );
    $stmt->bindParam( ':details', $details );
    $stmt->bindParam( ':public', $public );
    $stmt->bindParam( ':edited', $edited );
    $stmt->bindParam( ':id', $id );

    if ( $stmt->execute() ) {
      header ("location: home.php" );
    } else {
      logger ( "unable to update table: list for id: {$id} with details: {$details}", 2 );
    }

  }
} catch ( PDOException $e ) {
  print "Unable to update list with id: {$id} and details: {$details}<br/>";
}

function logger($message, $value) {
  $TIMESTAMP    = date("D M j Y G:i:s");
  $logFile      = 'register.log';

  if($value == 1) {
    // Set logging for INFO
    $message = $TIMESTAMP . " [INFO] " . $message . PHP_EOL;
  }

  if($value == 2) {
    $message = $TIMESTAMP ." [ERRO] " . $message . PHP_EOL;
  }

  return file_put_contents($logFile, $message, FILE_APPEND);
}

?>
<html>
  <head>
    <title>Storm</title>
  </head>

  <body>
    <h2>Home Page</h2>
    <p>Hello <?php print "$user"?></p>
    <a href="logout.php">Logout</a>
    <a href="home.php">Home</a>
    <h2 align="center">Currently Selected</h2>
    <table border="1px" width="100%">
      <tr>
        <th>Id</th>
        <th>Details</th>
        <th>Posted</th>
        <th>Edited</th>
        <th>Public</th>
      </tr>
      <?php
        if ( isset ( $_GET['id'] ) && !empty ( $_GET['id'] ) ) {
          $id = $_GET['id'];
          $_SESSION['id'] = $id;
          $id_exists = true;
          $query = "SELECT * FROM `list` WHERE id = '$id'";
          $row_count = $dbh->query( $query )->rowCount();
          $return_data = $dbh->query( $query )->fetchAll();

          if ( $row_count > 0 ) {
            foreach ( $return_data as $row ) {
              print "<tr>";
                print '<td align="center">' . $row['id'] . "</td>";
                print '<td align="center">' . $row['details'] . "</td>";
                print '<td align="center">' . $row['posted'] . "</td>";
                print '<td align="center">' . $row['edited'] . "</td>";
                print '<td align="center">' . $row['public'] . "</td>";
              print "</tr>";
            }
          } else {
            $id_exists = false;
          }
        }
      ?>
    </table>
    <br/>
    <?php
      if ( $id_exists ) {
        print '
          <form action="edit.php" method="POST">
            Enter new detail: <input type="text" name="details"/><br/>
            Public? <input type="checkbox" name="public[]" value="yes"/><br/>
            <input type="submit" value="Update" name="update"/>
          </form>';
      } else {
        print '<h2 align="center">There is no data to be edited.</h2>';
      }
    ?>

  </body>

</html>
