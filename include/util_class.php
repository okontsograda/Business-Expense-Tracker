<?php

class DB {

  public function connect_db() {

  // Production DB Connection
  $dbh = new PDO ( "mysql:host=localhost;dbname=id591640_rta", 'id591640_root', 'Ol3g@123' );

  // Development DB Connection
  //$dbh = new PDO ( "mysql:host=localhost;dbname=id591640_rta", 'root', 'root' );

  return $dbh;

  }

}

class Logger {

  public function log_message($message, $log_type) {
    $log_dir = "/var/log/kbrothers/";
    $TIMESTAMP    = date("D M j Y G:i:s");
    // Value - Detail Key
      /*
        1 -> INFO
        2 -> WARNING
        3 -> ERROR
      */

    if ( $log_type == 1 || $log_type == 2 ) $log_file = $log_dir . "general.log";
    if ( $log_type == 3 )                   $log_file = $log_dir . "error.log";

    // Logging for INFO
    if ( $value == 1 ) $message = "[" . $TIMESTAMP . "][INFO]" . $message . PHP_EOL;

    // Logging for WARNING
    if ( $value == 2 ) $message = "[" . $TIMESTAMP ."][WARN]" . $message . PHP_EOL;

    // Logging for ERROR
    if($value == 3) $message = "[" . $TIMESTAMP ."][ERRO]" . $message . PHP_EOL;


    return file_put_contents($log_file, $message, FILE_APPEND);
  }

}

class Timecard {

}

class Expense {

}

class Reports {

}


?>
