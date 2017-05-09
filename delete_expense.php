<?php
error_reporting(E_ALL);
ini_set('display_errors', TRUE);
ini_set('display_startup_errors', TRUE);

  session_start();

  if ( ! isset ( $_SESSION['user'] ) ) {
    header ( "location:index.php" );
  }

  if ( $_GET ) {

  // $dbh = new PDO ( "mysql:host=localhost;dbname=id591640_rta", 'id591640_root', 'Ol3g@123' );
  $dbh = new PDO ( "mysql:host=localhost;dbname=id591640_rta", 'root', 'root' );

    $id = $_GET['id'];
    $sql = ( "DELETE FROM `expense` WHERE `id` = {$id}" );

    if ( $dbh->query( $sql ) ) {
      header ( "location: home.php" );
    } else {
      print "Unable to delete id: {$id}<br/>";
    }


  }


?>
